require "net/http"
require "json"

module PlatformControl
  class AiAnalyzerService
    GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"

    def initialize(entry)
      @entry = entry
      @provider = AppConfig.get("ai_provider") || "gemini"
      @api_key = AppConfig.get("#{@provider}_api_key")
    end

    def analyze
      return { error: "#{@provider.titleize} API key not configured in AppConfig ('#{@provider}_api_key')" } if @api_key.blank?

      case @provider
      when "openai"
        analyze_openai
      else
        analyze_gemini
      end
    rescue => e
      { error: "Analyzer error: #{e.message}" }
    end

    private

    def analyze_gemini
      uri = URI(GEMINI_API_URL)
      uri.query = "key=#{@api_key}"

      response = post_request(uri, {
        contents: [ { parts: [ { text: prompt } ] } ],
        generationConfig: { temperature: 0.2, maxOutputTokens: 1024 }
      })

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        content = data.dig("candidates", 0, "content", "parts", 0, "text")
        render_content(content, "gemini-1.5-flash")
      else
        { error: "Gemini API Request failed: #{response.code} - #{response.body}" }
      end
    end

    def analyze_openai
      uri = URI(OPENAI_API_URL)

      response = post_request(uri, {
        model: "gpt-4o-mini",
        messages: [ { role: "user", content: prompt } ],
        temperature: 0.2,
        max_tokens: 1024
      }, { "Authorization" => "Bearer #{@api_key}" })

      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        content = data.dig("choices", 0, "message", "content")
        render_content(content, "gpt-4o-mini")
      else
        { error: "OpenAI API Request failed: #{response.code} - #{response.body}" }
      end
    end

    def post_request(uri, body, headers = {})
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.request_uri, { "Content-Type" => "application/json" }.merge(headers))
      request.body = body.to_json
      http.request(request)
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
