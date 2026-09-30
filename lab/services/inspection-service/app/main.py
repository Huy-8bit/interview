from app.api.routes import router
from app.messaging.handlers import HANDLERS
from platform_common.api import create_app

app = create_app(router, handlers=HANDLERS)
