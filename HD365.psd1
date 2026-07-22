@{
    RootModule        = 'HD365.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'a7c3e9f1-2b4d-4e8a-9c1f-6d5e8a0b3c72'
    Author            = 'HD365'
    CompanyName       = 'HelpDesk 365 AI'
    Copyright         = 'Copyright (c) HD365 contributors'
    Description       = 'HelpDesk 365 AI — Graph-first natural-language PowerShell assistant for Microsoft 365 administration with read/write phase gates and full write audit trail.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Start-HD365', 'Get-HD365AuditLog', 'Connect-HD365', 'Start-HD365Bridge')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('Microsoft365', 'Graph', 'HelpDesk', 'AI', 'ExchangeOnline', 'EntraID')
            ProjectUri   = 'https://github.com/PhillyOC/HD365'
            ReleaseNotes = 'v0.2.0: Provider-agnostic AI (CopilotChat, AzureOpenAI, OpenAI, Anthropic, Gemini, Together, Mistral, Ollama) with interactive /ai switcher; v0.1.0: CopilotChat planner, Graph batch bulk jobs, write gates, audit trail, Windows installer.'
        }
    }
}
