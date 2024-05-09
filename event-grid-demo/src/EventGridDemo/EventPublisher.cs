using Azure;
using Azure.Messaging.EventGrid;
using System;
using System.Threading.Tasks;

namespace EventGridDemo
{
    public class EventPublisher
    {
        private readonly EventGridPublisherClient _client;

        public EventPublisher()
        {
            string endpoint = Environment.GetEnvironmentVariable("EVENT_GRID_TOPIC_ENDPOINT");
            string accessKey = Environment.GetEnvironmentVariable("EVENT_GRID_KEY");

            _client = new EventGridPublisherClient(new Uri(endpoint), new AzureKeyCredential(accessKey));
        }

        public async Task SendEventsAsync()
        {
            Console.WriteLine("Sending events...");

            for (int i = 1; i <= 5; i++)
            {
                var eventGridEvent = new EventGridEvent(
                    subject: $"TestEvent-{i}",
                    eventType: "MyApp.Events.Test",
                    dataVersion: "1.0",
                    data: new { Message = $"Hello from Event Grid! Event #{i}" });

                await _client.SendEventAsync(eventGridEvent);
                Console.WriteLine($"Event {i} sent.");
            }

            Console.WriteLine("All events have been sent.");
        }
    }
}
