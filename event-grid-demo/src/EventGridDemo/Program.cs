using System;
using System.Threading.Tasks;

namespace EventGridDemo
{
    class Program
    {
        static async Task Main(string[] args)
        {
            Console.WriteLine("Initializing Event Publisher...");
            var publisher = new EventPublisher();
            await publisher.SendEventsAsync();
        }
    }
}
