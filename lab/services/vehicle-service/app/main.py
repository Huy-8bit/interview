from app.api.routes import router
from platform_common.api import create_app

app = create_app(router)
