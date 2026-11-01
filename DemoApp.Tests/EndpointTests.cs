using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;

namespace DemoApp.Tests;

public class EndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public EndpointTests(WebApplicationFactory<Program> factory)
        => _client = factory.CreateClient();

    [Fact]
    public async Task Health_returns_200_and_ok()
    {
        var res = await _client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var body = await res.Content.ReadFromJsonAsync<HealthDto>();
        Assert.Equal("ok", body!.Status);
    }

    [Fact]
    public async Task Home_page_shows_version()
    {
        var html = await _client.GetStringAsync("/");

        Assert.Contains("version", html);
    }

    private record HealthDto(string Status, string Version, string Environment);
}
