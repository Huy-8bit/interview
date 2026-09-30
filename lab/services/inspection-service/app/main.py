from app.api.routes import router
from app.messaging.cdc import TOPICS, decode
from app.messaging.handlers import HANDLERS
from app.reports.dispatcher import report_dispatch_loop, report_status_loop
from platform_common.api import create_app

app = create_app(router, handlers=HANDLERS, consumer_topics=TOPICS, decoder=decode,
                 extra_workers=(report_dispatch_loop, report_status_loop))
