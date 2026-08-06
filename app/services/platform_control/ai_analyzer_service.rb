require "ruby_llm"
require "json"

module PlatformControl
  class AiAnalyzerService
    PROVIDERS = {
      "gemini" => { label: "Gemini", key: "gemini_api_key", model: "gemini-2.5-flash", ruby_llm_provider: :gemini },
      "openai" => { label: "OpenAI", key: "openai_api_key", model: "gpt-4o-mini", ruby_llm_provider: :openai },
      "deepseek" => { label: "DeepSeek", key: "deepseek_api_key", model: "deepseek-chat", ruby_llm_provider: :deepseek },
      "claude" => { label: "Claude", key: "anthropic_api_key", model: "claude-haiku-4-5", ruby_llm_provider: :anthropic }
    }.freeze

    def initialize(entry)
      @entry = entry
      @provider = configured_provider
      @provider_config = PROVIDERS[@provider]
    end

    def analyze
      return { error: "No AI provider API key configured in AppConfig" } if @provider_config.blank?

      response = chat.ask(prompt)
      render_content(response.content, @provider_config[:model])
    rescue RubyLLM::Error => e
      { error: "#{@provider_config[:label]} API request failed: #{e.message}" }
    rescue => e
      { error: "Analyzer error: #{e.message}" }
    end

    private

    def configured_provider
      selected_provider = AppConfig.get("observation_deck_ai_provider")
      return selected_provider if provider_configured?(selected_provider)

      PROVIDERS.keys.find { |provider| provider_configured?(provider) }
    end

    def provider_configured?(provider)
      config = PROVIDERS[provider]
      config.present? && AppConfig.get(config[:key]).present?
    end

    def chat
      context.chat(
        model: @provider_config[:model],
        provider: @provider_config[:ruby_llm_provider]
      )
    end

    def context
      RubyLLM.context do |config|
        config.gemini_api_key = AppConfig.get("gemini_api_key")
        config.openai_api_key = AppConfig.get("openai_api_key")
        config.deepseek_api_key = AppConfig.get("deepseek_api_key")
        config.anthropic_api_key = AppConfig.get("anthropic_api_key")
      end
    end

    def render_content(content, model)
      if content.present?
        { html: Commonmarker.to_html(content), model: model }
      else
        { error: "Empty response from AI provider" }
      end
    end

    def prompt
      <<~PROMPT
        You are an expert Ruby on Rails observability assistant.
        Analyze this system log entry and provide a concise, actionable summary for a developer.

        ENTRY TYPE: #{@entry.entry_type}
        PATH/ACTION: #{@entry.path}
        STATUS: #{@entry.status}
        DURATION: #{@entry.duration}ms
        PAYLOAD: #{JSON.pretty_generate(@entry.payload)}
        TAGS: #{@entry.tags.join(', ')}

        Provide your response in this exact Markdown format:
        ### 🔍 Summary
        (One sentence explaining what happened in plain English)

        ### 💡 Insight
        (Technical explanation of why it might be failing or slow. If it's a 200 OK, explain what was accomplished)

        ### 🛠️ Recommendation
        (Specific, actionable steps for the developer)

        Keep it brief and professional.
      PROMPT
    end
  end
end
