class DomainError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code


class TransientError(Exception):
    """Retrying may succeed; no business transaction has committed."""
