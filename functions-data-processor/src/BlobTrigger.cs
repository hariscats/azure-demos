using System;
using System.IO;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;

namespace DataProcessingFunction
{
    public static class DataCleansingFunction
    {
        [FunctionName("DataCleansingFunction")]
        public static void Run(
            [BlobTrigger("raw-data/{name}", Connection = "AzureWebJobsStorage")] Stream myBlob,
            [Blob("reports/{name}", FileAccess.Write, Connection = "AzureWebJobsStorage")] Stream outputBlob,
            string name,
            ILogger log)
        {
            log.LogInformation($"Processing blob\n Name: {name} \n Size: {myBlob.Length} Bytes");

            try
            {
                ProcessData(myBlob, outputBlob);
                log.LogInformation($"Data processing and report generation completed for {name}");
            }
            catch (Exception ex)
            {
                log.LogError($"Error during data processing for {name}: {ex.Message}");
            }
        }

        private static void ProcessData(Stream inputData, Stream outputData)
        {
            // Data cleansing and transformation logic should go here
            // Currently, this just copies input to output
            inputData.CopyTo(outputData);
        }
    }
}
