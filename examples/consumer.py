"""Read Event Hubs messages for smoke testing. pip install azure-eventhub azure-identity"""
import os
from azure.eventhub import EventHubConsumerClient
from azure.identity import DefaultAzureCredential

namespace = os.environ["EVENTHUB_NAMESPACE"]  # e.g. evhns-example.servicebus.windows.net
hub = os.environ.get("EVENTHUB_NAME", "eh-vm-logs")
client = EventHubConsumerClient(
    fully_qualified_namespace=namespace,
    eventhub_name=hub,
    consumer_group="$Default",
    credential=DefaultAzureCredential(),
)

def on_event(partition_context, event):
    print(f"partition={partition_context.partition_id} body={event.body_as_str()}")
    # Demo: no checkpoints; use BlobCheckpointStore for production consumers.

with client:
    client.receive(on_event=on_event, starting_position="-1")
