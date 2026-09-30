from app.api.routes import router
from app.messaging.handlers import HANDLERS
from app.services.warranties import expiry_loop
from platform_common.api import create_app

app = create_app(router, handlers=HANDLERS, extra_workers=(expiry_loop,))
