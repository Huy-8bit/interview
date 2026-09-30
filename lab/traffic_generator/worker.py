import asyncio
import json
import math
import random
import secrets
import signal
import time
from collections import deque
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

import httpx

from traffic_generator.config import Config, RateControl
from traffic_generator.metrics import Metrics, emit

MODELS = {"VinFast": ["VF 6", "VF 8"], "Toyota": ["Corolla", "Camry"], "Honda": ["Civic", "CR-V"], "Ford": ["Ranger", "Everest"], "Hyundai": ["Accent", "Tucson"]}
OWNERS = ["Nguyen An", "Tran Binh", "Le Chi", "Pham Dung", "Hoang Ha"]
FAILURES = ["battery issue", "brake issue", "engine warning", "sensor failure", "tire damage"]
VIN_ALPHABET = "ABCDEFGHJKLMNPRSTUVWXYZ0123456789"


class RequestFailed(Exception):
    pass


class Pacer:
    """Evenly spaces HTTP attempts across all virtual users; rate 0 disables pacing.

    Slots left unused while every user was busy elsewhere can be reclaimed for up to
    `burst` seconds, so the long-run rate reaches the target without exceeding it.
    """

    def __init__(self, rate, burst=0.5):
        self.rate = rate
        self.burst = burst
        self.next_slot = 0.0
        self.wait_seconds = 0.0

    def set_rate(self, rate):
        self.rate = rate
        # New attempts must not queue behind slots reserved at a slower rate.
        self.next_slot = min(self.next_slot, time.monotonic() + (1 / rate if rate else 0))

    async def acquire(self):
        if self.rate <= 0:
            return
        now = time.monotonic()
        slot = max(self.next_slot, now - self.burst)
        self.next_slot = slot + 1 / self.rate  # No await between reading and reserving the slot.
        if slot > now:
            await asyncio.sleep(slot - now)
            self.wait_seconds += slot - now


def needed_virtual_users(target_rps, requests, busy_seconds, active, maximum):
    """Little's law on the unpaced per-user rate. Flows are bursty, so the pool keeps 25%
    headroom and the pacer, not idle users, stays the bottleneck."""
    if busy_seconds <= 0:
        return max(1, active // 2)  # Every user spent the whole window waiting on the pacer.
    needed = math.ceil(target_rps * 1.25 * busy_seconds / requests)
    # Move at most 2x per step either way; windows spanning a target change are noisy.
    return max(1, min(needed, max(active * 2, active + 1), maximum), active // 2)


class Traffic:
    def __init__(self, config=None, *, transport=None):
        self.config = config or Config()
        self.run_id = str(uuid4())
        self.metrics = Metrics()
        self.stop = asyncio.Event()
        self.load_started = time.monotonic()
        self.load_claimed = 0
        self.tasks = []
        self.rate = RateControl(target_rps=self.config.target_rps, interval_ms=self.config.interval_ms,
                                virtual_users=min(self.config.virtual_users, self.config.max_virtual_users))
        self.pacer = Pacer(self.rate.target_rps)
        self.vus = {}
        self.desired_vus = self.rate.virtual_users
        self.current_rps = 0.0
        self.vu_seconds = 0.0
        self.sampled_at = time.monotonic()
        self.samples = deque(maxlen=11)  # One per reporter tick: a ~10s window.
        self.next_scale = 0.0
        self.control_mtime = None
        self.control_version = None
        self.http = httpx.AsyncClient(
            timeout=self.config.timeout, transport=transport,
            limits=httpx.Limits(max_connections=self.config.max_virtual_users * 4, max_keepalive_connections=self.config.max_virtual_users * 2),
        )

    async def close(self):
        await self.http.aclose()

    async def request(self, flow, action, service, method, endpoint, *, allowed=(), **kwargs):
        headers = kwargs.pop("headers", {})
        for attempt in range(self.config.max_retries + 1):
            await self.pacer.acquire()
            request_id, started = str(uuid4()), time.monotonic()
            response, status, error = None, None, None
            try:
                # HTTPX has per-phase inactivity timeouts. This is a whole-attempt deadline.
                async with asyncio.timeout(self.config.timeout):
                    response = await self.http.request(
                        method, self.config.urls[service] + endpoint,
                        headers={**headers, "X-Correlation-ID": flow["correlation_id"], "X-Request-ID": request_id},
                        **kwargs,
                    )
                status = response.status_code
                if status >= 400:
                    try:
                        error = response.json().get("error", {}).get("code", "http_error")
                    except (ValueError, AttributeError):
                        error = "http_error"
            except (httpx.TransportError, TimeoutError) as exc:
                error = type(exc).__name__
            latency = (time.monotonic() - started) * 1000
            accepted = response is not None and (200 <= status < 300 or status in allowed)
            retryable = status is None or status >= 500
            expected_error = status is not None and status >= 400 and status in allowed
            self.metrics.request(status, latency, expected_error)
            emit(action, flow=flow, request_id=request_id, response_request_id=response.headers.get("X-Request-ID") if response is not None else None,
                 target_service=service, endpoint=endpoint, method=method, status_code=status,
                 latency_ms=round(latency, 2), attempt=attempt + 1,
                 result="expected_status" if expected_error else "ok" if accepted else "error", error=error,
                 cache=response.headers.get("X-Cache") if response is not None else None,
                 read_source=response.headers.get("X-Read-Source") if response is not None else None)
            if accepted:
                return response
            if not retryable or attempt == self.config.max_retries:
                raise RequestFailed(f"{action}: status={status}, error={error}, attempts={attempt + 1}")
            self.metrics.counts["retries"] += 1
            delay = min(self.config.backoff_ms / 1000 * 2 ** attempt, 5) * random.uniform(0.8, 1.2)
            emit("retry_backoff", flow=flow, retry_action=action, next_attempt=attempt + 2, delay_ms=round(delay * 1000), error=error)
            await asyncio.sleep(delay)
        raise AssertionError("Unreachable")

    async def converge(self, flow, action, operation):
        try:
            async with asyncio.timeout(self.config.convergence_timeout):
                while True:
                    result = await operation()
                    if result is not None:
                        return result
                    self.metrics.counts["convergence_polls"] += 1
                    await asyncio.sleep(0.25)
        except TimeoutError as exc:
            raise RequestFailed(f"{action}: convergence deadline reached") from exc

    async def create_vehicle(self, flow):
        manufacturer = random.choice(list(MODELS))
        body = dict(
            vin="TRF" + "".join(secrets.choice(VIN_ALPHABET) for _ in range(14)),
            manufacturer=manufacturer, model=random.choice(MODELS[manufacturer]),
            production_year=random.randint(2000, min(datetime.now(UTC).year, 2100)),
            owner_name=random.choice(OWNERS), simulation_run_id=self.run_id,
        )
        failure = None
        try:
            response = await self.request(flow, "create_vehicle", "vehicle", "POST", "/vehicles", allowed=(409,), json=body)
            if response.status_code == 201:
                return response.json()
            failure = RequestFailed("Vehicle VIN conflict")
        except RequestFailed as exc:
            failure = exc
        # A timeout/5xx may follow a successful commit. Reuse the same VIN for
        # every attempt, then reconcile via the public primary-backed list API.
        response = await self.request(flow, "reconcile_vehicle", "vehicle", "GET", "/vehicles", params={"vin": body["vin"]})
        rows = response.json()
        if len(rows) == 1 and all(rows[0].get(k) == v for k, v in body.items()):
            self.metrics.counts["reconciled_vehicle_creates"] += 1
            return rows[0]
        raise failure

    async def observe_replica(self, flow, path):
        started = time.monotonic()
        for target in map(int, self.config.replica_delays.split(",")):
            await asyncio.sleep(max(0, target / 1000 - (time.monotonic() - started)))
            response = await self.request(flow, "read_replica", "vehicle", "GET", path, allowed=(404,), params={"consistency": "eventual"})
            if response.status_code == 404 and response.json().get("error", {}).get("code") != "vehicle_not_found":
                raise RequestFailed("Unexpected replica read error")
            source = response.headers.get("X-Read-Source")
            self.metrics.counts["replica_stale_reads" if response.status_code == 404 else "replica_fallback_reads" if source == "primary-fallback" else "replica_visible_reads"] += 1
            emit("replication_observation", flow=flow, target_delay_ms=target,
                 elapsed_ms=round((time.monotonic() - started) * 1000, 2), status_code=response.status_code,
                 read_source=source, visible=response.status_code == 200,
                 result="eventual_miss" if response.status_code == 404 else "visible")

    async def observe_cache(self, flow, path, expected, action):
        response = await self.request(flow, action, "vehicle", "GET", path)
        observed = response.headers.get("X-Cache")
        self.metrics.counts["cache_" + str(observed).lower()] += 1
        emit("cache_observation", flow=flow, expected=expected, observed=observed, matched=observed == expected, observation=action)
        return response.json()

    async def lifecycle(self, virtual_user):
        flow_id = str(uuid4())
        flow = dict(run_id=self.run_id, flow_id=flow_id, correlation_id=flow_id, virtual_user=virtual_user)
        self.metrics.counts["flows_started"] += 1
        emit("flow_started", flow=flow)
        try:
            async with asyncio.timeout(self.config.flow_timeout):
                vehicle = await self.create_vehicle(flow)
                flow["vehicle_id"] = vehicle["id"]
                self.metrics.counts["created_vehicles"] += 1
                path = "/vehicles/" + vehicle["id"]
                await self.observe_replica(flow, path)
                await self.observe_cache(flow, path, "MISS", "cache_first_get")
                await self.observe_cache(flow, path, "HIT", "cache_second_get")
                owner = random.choice(OWNERS) + " updated " + flow_id[:8]
                await self.request(flow, "update_vehicle", "vehicle", "PATCH", path, json={"owner_name": owner, "status": "ACTIVE"})
                after = await self.observe_cache(flow, path, "MISS", "cache_after_invalidation")
                if after["owner_name"] != owner:
                    self.metrics.counts["stale_cache_observations"] += 1
                    emit("cache_value_stale", flow=flow, result="degraded", error="Updated owner not visible through cache")
                if random.random() < self.config.error_rate:
                    r = await self.request(flow, "intentional_validation_error", "vehicle", "PATCH", path, json={"production_year": 1800}, allowed=(422,))
                    if r.status_code != 422:
                        raise RequestFailed("Invalid production year was not rejected")
                    self.metrics.counts["injected_errors"] += 1
                key = str(uuid4())
                body = dict(vehicle_id=vehicle["id"], inspection_type=random.choice(["DELIVERY", "PERIODIC", "DIAGNOSTIC"]), notes="Traffic flow " + flow_id)

                async def create_inspection():
                    async def attempt():
                        r = await self.request(flow, "create_inspection", "inspection", "POST", "/inspections", headers={"Idempotency-Key": key}, json=body, allowed=(409,))
                        if r.status_code == 409:
                            if r.json().get("error", {}).get("code") not in ("vehicle_projection_not_ready", "warranty_projection_not_ready"):
                                raise RequestFailed("Unexpected inspection business conflict")
                            return None
                        return r.json()
                    return await self.converge(flow, "vehicle_projection", attempt)

                duplicated = random.random() < self.config.duplicate_rate
                if duplicated:
                    async with asyncio.TaskGroup() as group:
                        first_task = group.create_task(create_inspection())
                        second_task = group.create_task(create_inspection())
                    first, second = first_task.result(), second_task.result()
                    if first["id"] != second["id"]:
                        raise RequestFailed("Duplicate Idempotency-Key produced different inspections")
                    inspection = first
                    listing = await self.request(flow, "verify_single_inspection", "inspection", "GET", "/inspections", params={"vehicle_id": vehicle["id"]})
                    if len(listing.json()) != 1 or listing.json()[0]["id"] != first["id"]:
                        raise RequestFailed("Duplicate inspection visible via API")
                    self.metrics.counts["duplicate_requests_verified"] += 1
                    emit("idempotency_verified", flow=flow, inspection_id=first["id"], idempotency_key=key, unique_inspections=1)
                else:
                    inspection = await create_inspection()
                flow["inspection_id"] = inspection["id"]
                self.metrics.counts["created_inspections"] += 1
                failed = random.random() < self.config.fail_rate
                result = "FAIL" if failed else "PASS"
                complete = {"result": result}
                if failed:
                    complete["failure_reason"] = random.choice(FAILURES)
                await self.request(flow, "complete_inspection", "inspection", "POST", f"/inspections/{inspection['id']}/complete", json=complete)
                self.metrics.counts["failed_inspections" if failed else "passed_inspections"] += 1

                async def warranty_ready():
                    r = await self.request(flow, "query_warranty", "warranty", "GET", f"/warranties/vehicle/{vehicle['id']}/active", allowed=(404,))
                    if r.status_code == 404 and r.json().get("error", {}).get("code") != "warranty_not_ready":
                        raise RequestFailed("Unexpected warranty query error")
                    return r.json() if r.status_code == 200 else None

                coverage = await self.converge(flow, "warranty", warranty_ready)
                flow["warranty_id"] = coverage["warranty_id"]
                if failed:
                    async def repair_ready():
                        r = await self.request(flow, "query_repair", "repair", "GET", "/repairs", params={"inspection_id": inspection["id"]})
                        rows = r.json()
                        if len(rows) > 1:
                            raise RequestFailed("Multiple repairs for one inspection")
                        return rows[0] if rows else None
                    repair = await self.converge(flow, "repair", repair_ready)
                    flow["repair_id"] = repair["id"]
                    self.metrics.counts["created_repairs"] += 1
                deleted = False
                if random.random() < self.config.delete_rate:
                    r = await self.request(flow, "delete_simulation_vehicle", "vehicle", "DELETE", path, headers={"X-Simulation-Run-ID": self.run_id}, allowed=(404,))
                    # A retried DELETE may see 404 after the original request committed.
                    absent = await self.request(flow, "verify_deleted_vehicle", "vehicle", "GET", "/vehicles", params={"vin": vehicle["vin"]})
                    if absent.json():
                        raise RequestFailed("Deleted simulation vehicle still exists on primary")
                    deleted = True
                    self.metrics.counts["deleted_vehicles"] += 1
                    emit("cdc_delete_requested", flow=flow, status_code=r.status_code, result="primary_row_absent")
                self.metrics.counts["flows_completed"] += 1
                emit("flow_completed", flow=flow, inspection_result=result, duplicated=duplicated, deleted=deleted, result="ok")
                return flow
        except asyncio.CancelledError:
            self.metrics.counts["flows_cancelled"] += 1
            emit("flow_cancelled", flow=flow, result="shutdown")
            raise
        except Exception as exc:
            self.metrics.counts["flows_failed"] += 1
            emit("flow_failed", flow=flow, result="error", error=type(exc).__name__ + ": " + str(exc)[:500])
            return None

    def write_status(self, state):
        value = dict(run_id=self.run_id, heartbeat_unix=time.time(), state=state, mode=self.config.mode,
                     enabled=self.config.enabled, virtual_users=self.desired_vus, active_virtual_users=len(self.vus),
                     target_rps=self.rate.target_rps, current_rps=round(self.current_rps, 2), interval_ms=self.rate.interval_ms,
                     control_version=self.control_version, **self.metrics.snapshot())
        path = Path(self.config.status_file)
        temp = path.with_suffix(".tmp")
        temp.write_text(json.dumps(value))
        temp.replace(path)
        return value

    def apply_control(self):
        path = Path(self.config.control_file)
        try:
            mtime = path.stat().st_mtime_ns
        except FileNotFoundError:
            return
        if mtime == self.control_mtime:
            return
        self.control_mtime = mtime
        try:
            data = json.loads(path.read_text())
            rate = RateControl.model_validate({**self.rate.model_dump(), **data})
            if rate.virtual_users > self.config.max_virtual_users:
                raise ValueError(f"virtual_users exceeds TRAFFIC_MAX_VIRTUAL_USERS={self.config.max_virtual_users}")
        except (OSError, TypeError, ValueError) as exc:
            emit("rate_control_rejected", error=str(exc)[:500])
            return
        self.rate, self.control_version, self.next_scale = rate, data.get("version"), 0.0
        self.pacer.set_rate(rate.target_rps)
        emit("rate_changed", control_version=self.control_version, **rate.model_dump())

    def adjust(self):
        now = time.monotonic()
        self.vu_seconds += len(self.vus) * (now - self.sampled_at)
        self.sampled_at = now
        total = self.metrics.counts["total_requests"]
        self.samples.append((now, total, self.pacer.wait_seconds, self.vu_seconds))
        started, first_total, first_wait, first_vu_seconds = self.samples[0]
        elapsed, requests = now - started, total - first_total
        self.current_rps = requests / elapsed if elapsed else 0.0
        if self.rate.target_rps <= 0:
            self.desired_vus = self.rate.virtual_users
        elif now >= self.next_scale and elapsed >= 5 and requests:
            busy = (self.vu_seconds - first_vu_seconds) - (self.pacer.wait_seconds - first_wait)
            self.desired_vus = needed_virtual_users(self.rate.target_rps, requests, busy, len(self.vus), self.config.max_virtual_users)
            self.next_scale = now + 5
        self.scale()
        self.metrics.gauges.update(traffic_target_rps=self.rate.target_rps, traffic_virtual_users=len(self.vus))

    def scale(self):
        # Spawns missing users; surplus users exit on their own after the current flow.
        if self.config.mode != "continuous" or not self.config.enabled or self.stop.is_set():
            return
        for number in range(1, self.desired_vus + 1):
            if number not in self.vus:
                self.vus[number] = asyncio.create_task(self.virtual_user(number))

    async def reporter(self):
        next_summary = 0
        while not self.stop.is_set():
            self.apply_control()
            self.adjust()
            value = self.write_status("running" if self.config.enabled else "disabled")
            if time.monotonic() >= next_summary:
                emit("summary", **value)
                next_summary = time.monotonic() + self.config.summary_interval
            try:
                await asyncio.wait_for(self.stop.wait(), timeout=1)
            except TimeoutError:
                pass

    async def load_create(self, number):
        if self.load_claimed >= self.config.load_test_max_vehicles or time.monotonic() - self.load_started >= self.config.load_test_duration_seconds:
            await self.stop.wait()  # Keep the endpoint and heartbeat available after bounded load.
            return
        self.load_claimed += 1  # No await between cap check and claim.
        flow = dict(run_id=self.run_id, correlation_id=str(uuid4()), virtual_user=number)
        try:
            vehicle = await self.create_vehicle(flow)
            self.metrics.counts["created_vehicles"] += 1
            self.metrics.counts["load_creates"] += 1
            emit("load_vehicle_created", flow=flow, vehicle_id=vehicle["id"])
        except Exception as exc:
            self.metrics.counts["flows_failed"] += 1
            emit("load_create_failed", flow=flow, error=type(exc).__name__)

    async def virtual_user(self, number):
        try:
            while not self.stop.is_set() and number <= self.desired_vus:
                await (self.load_create(number) if self.config.load_test_mode else self.lifecycle(number))
                if number > self.desired_vus:
                    break
                try:
                    await asyncio.wait_for(self.stop.wait(), timeout=max(self.rate.interval_ms / 1000, 0.001))
                except TimeoutError:
                    pass
        finally:
            if self.vus.get(number) is asyncio.current_task():
                del self.vus[number]

    async def run(self):
        self.metrics.start_server(self.config.metrics_port)
        self.load_started = time.monotonic()
        loop = asyncio.get_running_loop()
        for signum in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(signum, self.stop.set)
        # Runtime rate overrides last for one run, like counters and run_id.
        Path(self.config.control_file).unlink(missing_ok=True)
        emit("started", run_id=self.run_id, mode=self.config.mode, enabled=self.config.enabled,
             virtual_users=self.rate.virtual_users, interval_ms=self.rate.interval_ms,
             target_rps=self.rate.target_rps, max_virtual_users=self.config.max_virtual_users)
        reporter = asyncio.create_task(self.reporter())
        success = True
        try:
            if not self.config.enabled:
                if self.config.mode == "continuous":
                    await self.stop.wait()
            elif self.config.mode == "scenario":
                lifecycle = asyncio.create_task(self.lifecycle(1))
                stopping = asyncio.create_task(self.stop.wait())
                self.tasks = [lifecycle, stopping]
                await asyncio.wait(self.tasks, return_when=asyncio.FIRST_COMPLETED)
                success = lifecycle.done() and not lifecycle.cancelled() and lifecycle.result() is not None
            else:
                self.scale()
                await self.stop.wait()
        finally:
            self.stop.set()
            tasks = [*self.tasks, *self.vus.values()]
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            await reporter
            emit("summary_final", **self.write_status("stopped"))
            await self.close()
            await asyncio.to_thread(self.metrics.close_server)
        return success
