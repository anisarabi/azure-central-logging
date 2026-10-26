import logging
import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

@app.route(route="emit-log", methods=["GET"])
def emit_log(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("CENTRAL_LOGGING_LAB INFO")
    logging.warning("CENTRAL_LOGGING_LAB WARNING")
    logging.error("CENTRAL_LOGGING_LAB ERROR")

    return func.HttpResponse("Logs generated successfully", status_code=200)