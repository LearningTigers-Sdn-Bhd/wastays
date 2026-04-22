require "net/http"
require "json"

module PlatformControl
  class AiAnalyzerService
    GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"

    def initialize(entry)
      @entry = entry
      @api_key = AppConfig.get("gemini_api_key")
    end

    def analyze
      return { error: "Gemini API key not configured in AppConfig ('gemini_api_key')" } if @api_key.blank?

      uri = URI(GEMINI_API_URL)
      uri.query = "key=#{@api_key}"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = {
        contents: [
          {
            parts: [
              { text: prompt }
            ]
          }
        ],
        generationConfig: {
          temperature: 0.2,
          topP: 0.8,
          topK: 40,
          maxOutputTokens: 1024
        }
      }.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        parse_response(JSON.parse(response.body))
      else
        { error: "API Request failed: #{response.code} - #{response.body}" }
      end
    rescue => e
      { error: "Analyzer error: #{e.message}" }
    end

    private

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

    def parse_response(data)
      content = data.dig("candidates", 0, "content", "parts", 0, "text")
      if content.present?
        { html: Commonmarker.to_html(content) }
      else
        { error: "Empty response from Gemini" }
      end
    end
  end
end
