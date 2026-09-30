from app.api.routes import router
from app.services.warranty_provision import provision_loop
from platform_common.api import create_app

app = create_app(router, extra_workers=(provision_loop,))
