using Azure.AI.Inference;
using Azure.Identity;

namespace ZavaStorefront.Services;

public class ChatService
{
    private readonly ChatCompletionsClient _client;
    private readonly ILogger<ChatService> _logger;
    private readonly string _endpoint;

    public ChatService(IConfiguration configuration, ILogger<ChatService> logger)
    {
        _logger = logger;

        _endpoint = configuration["AzureAIFoundry:Endpoint"]
            ?? throw new InvalidOperationException("AzureAIFoundry:Endpoint is not configured.");

        // DefaultAzureCredential uses managed identity (via AZURE_CLIENT_ID) on Azure
        // and falls back to Azure CLI / developer credentials when running locally.
        var clientId = configuration["AZURE_CLIENT_ID"];
        var credential = new DefaultAzureCredential(
            new DefaultAzureCredentialOptions { ManagedIdentityClientId = clientId });

        _client = new ChatCompletionsClient(
            new Uri(_endpoint),
            credential);
    }

    public async Task<string> SendMessageAsync(string userMessage)
    {
        _logger.LogInformation("Sending message to endpoint {Endpoint}", _endpoint);

        var options = new ChatCompletionsOptions
        {
            // Model is NOT set — the deployment name is encoded in the endpoint URL
            Messages =
            {
                new ChatRequestSystemMessage(
                    "You are a helpful shopping assistant for Zava Storefront. " +
                    "Help customers with questions about products and pricing."),
                new ChatRequestUserMessage(userMessage)
            },
            MaxTokens = 512
        };

        var response = await _client.CompleteAsync(options);
        return response.Value.Content;
    }
}
