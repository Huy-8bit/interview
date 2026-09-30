from app.api.routes import router
from app.messaging.cdc import TOPICS, decode
from app.messaging.handlers import HANDLERS
from platform_common.api import create_app

app = create_app(router, handlers=HANDLERS, consumer_topics=TOPICS, decoder=decode)
