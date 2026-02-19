using Azure;
using Azure.AI.Inference;

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
        var apiKey = configuration["AzureAIFoundry:ApiKey"]
            ?? throw new InvalidOperationException("AzureAIFoundry:ApiKey is not configured.");

        _client = new ChatCompletionsClient(
            new Uri(_endpoint),
            new AzureKeyCredential(apiKey));
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
