using System.Reflection;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// 1.0.<build number> from CI, 1.0.0 on a dev machine
var version = (typeof(Program).Assembly
    .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "dev")
    .Split('+')[0];

var envName = app.Environment.EnvironmentName;
var banner = app.Configuration["Banner"] ?? "LOCAL";
var color = envName == "Production" ? "#1b7f3b" : "#0b5cad";

// landing page, color + banner change per environment so dev/prod are easy to tell apart
app.MapGet("/", () => Results.Content($$"""
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>DemoApp</title>
      <style>
        body { font-family: "Segoe UI", sans-serif; background: {{color}}; color: #fff;
               display: flex; align-items: center; justify-content: center;
               height: 100vh; margin: 0; }
        .card { text-align: center; }
        h1 { font-size: 3rem; margin: 0 0 .5rem; }
        p { font-size: 1.5rem; margin: .25rem; opacity: .9; }
      </style>
    </head>
    <body>
      <div class="card">
        <h1>{{banner}}</h1>
        <p>version {{version}}</p>
        <p>environment: {{envName}}</p>
      </div>
    </body>
    </html>
    """, "text/html"));

// used by deploy.ps1 after every deploy. Health:ForceFail is the rollback demo switch
app.MapGet("/health", () =>
    app.Configuration.GetValue<bool>("Health:ForceFail")
        ? Results.StatusCode(503)
        : Results.Ok(new { status = "ok", version, environment = envName }));

app.Run();

// needed so the test project can use WebApplicationFactory<Program>
public partial class Program { }
