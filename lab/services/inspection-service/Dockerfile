FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/opt/common:/app
WORKDIR /app
COPY requirements.txt requirements.lock /opt/
COPY services/inspection-service/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt -c /opt/requirements.lock && useradd --create-home app
COPY common/platform_common /opt/common/platform_common
COPY services/inspection-service /app
COPY scripts /opt/scripts
COPY pyproject.toml /app/pyproject.toml
USER app
EXPOSE 8000
CMD ["sh", "/opt/scripts/start.sh"]
