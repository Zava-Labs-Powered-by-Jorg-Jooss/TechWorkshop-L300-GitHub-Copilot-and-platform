using Microsoft.AspNetCore.Mvc;
using ZavaStorefront.Services;

namespace ZavaStorefront.Controllers;

public class ChatController : Controller
{
    private readonly ChatService _chatService;

    public ChatController(ChatService chatService)
    {
        _chatService = chatService;
    }

    public IActionResult Index() => View();

    [HttpPost]
    public async Task<IActionResult> SendMessage([FromBody] ChatRequest request)
    {
        if (string.IsNullOrWhiteSpace(request?.Message))
            return BadRequest("Message cannot be empty.");

        var reply = await _chatService.SendMessageAsync(request.Message);
        return Ok(new { reply });
    }
}

public class ChatRequest
{
    public string? Message { get; set; }
}
