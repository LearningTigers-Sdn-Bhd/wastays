# frozen_string_literal: true

require "ruby_llm"

module AiConcierge
  module Agents
    # Says a finished reply differently.
    #
    # Everything the guest is told is still computed in Ruby -- the price, the
    # dates, the option numbers, the quote link -- and this runs afterwards, on
    # the finished sentence. The model is never asked what to say, only how to
    # say it, which is the seam the tool-calling loop was deliberately built to
    # leave open: a model that authored the reply could author the price too.
    #
    # It reads which language the guest wrote in, and that is the only thing
    # about language it is asked for. Which language the reply goes out in is
    # worked out in Ruby from what the guest established, and handed down as an
    # instruction -- a model given a resolved target answers in the right
    # language far more often than one given a rule to evaluate mid-prompt, and
    # a model asked to decide has told nobody anything that can be checked.
    #
    # The reading rides along on a call that is already reading the message to
    # know what register to answer in, so it costs no round trip.
    class ReplyStylist
      class ReplyStylistError < StandardError; end

      LLM_TIMEOUT = 15

      # Zero, against a provider default of 1.0 that nothing here ever set.
      # This rewrites a sentence that is already finished and already correct,
      # so every degree of freedom is a chance to lose a fact or drift into
      # another language, and none of them is a chance to do better.
      TEMPERATURE = 0

      # `language` is what the model says it wrote in. `guest_language` is what
      # it read in the guest's message, and is nil when the message had no
      # words to read -- "1", "yes", a room name. They are different claims and
      # only one of them is about the guest, which is why they are separate.
      Styled = Struct.new(:text, :language, :guest_language, keyword_init: true)

      # `basic` is absent on purpose: it means "do not run this at all", and it
      # is the default every hotel has until someone changes it.
      TONES = {
        "business" => "Formal and efficient. Address the guest respectfully, no exclamation marks, no small talk.",
        "cheerful" => "Warm and upbeat. Sound pleased to help, but stay brief -- one friendly touch, not three."
      }.freeze

      # A message with no letters in it cannot be written in any language, so
      # there is nothing here to notice and nothing to translate -- "1", "2",
      # "21/08" keep the thread exactly as it is, for free.
      #
      # Anything the guest actually wrote gets read, even for a hotel that never
      # picked a tone. The alternative gate -- run only once the thread is
      # already non-English -- can never come true, because this is the only
      # thing that ever sets a thread's language.
      WORDED = /[[:alpha:]]/

      def self.styles?(hotel:, thread_language:, guest_message:)
        return true if TONES.key?(hotel.ai_concierge_tone)
        return true if thread_language != Conversation::DEFAULT_LANGUAGE

        guest_message.to_s.match?(WORDED)
      end

      def initialize(hotel:, template:, guest_message:, thread_language:)
        @hotel = hotel
        @template = template.to_s
        @guest_message = guest_message.to_s.strip
        @thread_language = thread_language.presence || Conversation::DEFAULT_LANGUAGE
      end

      def call
        response = Timeout.timeout(LLM_TIMEOUT) { chat.ask(prompt) }
        Providers::UsageLog.call(response, hotel: hotel, stage: :stylist)
        parse(response&.content.to_s)
      rescue Timeout::Error
        raise ReplyStylistError, "Reply stylist timed out after #{LLM_TIMEOUT}s"
      rescue RubyLLM::Error => e
        raise ReplyStylistError, "Reply stylist API error: #{e.message}"
      end

      private

      attr_reader :hotel, :template, :guest_message, :thread_language

      def chat = Providers::RubyLlmClient.new(hotel: hotel).chat.with_temperature(TEMPERATURE)

      # Lenient about the wrapper, strict about the contents: models fence JSON
      # in markdown often enough that refusing it would fail turns over
      # punctuation. A body that is not JSON at all is a real failure and the
      # caller sends the template.
      def parse(content)
        json = content[/\{.*\}/m]
        raise ReplyStylistError, "Reply stylist returned no JSON" if json.blank?

        parsed = JSON.parse(json)
        text = parsed["text"].to_s.strip
        raise ReplyStylistError, "Reply stylist returned an empty reply" if text.blank?

        Styled.new(
          text: text,
          language: parsed["language"].to_s.strip.presence || thread_language,
          guest_language: language_code(parsed["guest_language"])
        )
      rescue JSON::ParserError => e
        raise ReplyStylistError, "Reply stylist returned malformed JSON: #{e.message}"
      end

      # A message with nothing to read establishes nothing, and the thread's
      # language stays where it was. Models write that absence three ways --
      # the JSON null, the word, and the ISO code for "undetermined" -- and all
      # three mean the same thing here.
      def language_code(value)
        code = value.to_s.strip.downcase
        code if code.present? && !%w[null und].include?(code)
      end

      def prompt
        <<~PROMPT
          Rewrite a hotel's reply to a guest. Do not answer the guest yourself.

          THE REPLY TO REWRITE:
          #{template}

          WHAT THE GUEST JUST WROTE:
          #{guest_message.presence || "(nothing)"}

          TONE: #{tone_instruction}

          LANGUAGE:
          - Write the reply in #{thread_language}.
          - Unless the guest's message above is itself written in another
            language. Then write the reply in that language instead.

          RULES:
          - Keep every number, price, time and currency exactly as written, in
            digits. Never spell a number out in words.
          - Keep every link character for character. Never shorten or relabel one.
          - Keep room type and rate plan names exactly as written, in their
            original language. The guest types these back to us, and a
            translated name matches nothing.
          - Keep the line breaks, the list shape and the *asterisks* around bold text.
          - Do not add, remove or soften any fact. Do not add a greeting or a
            sign-off that is not already there.

          Reply with JSON only, with all three keys:
          {"guest_language": "<ISO 639-1 code for the language the guest's message is written in, or null if it is only numbers, punctuation or a name>",
           "language": "<ISO 639-1 code for the language you wrote the reply in>",
           "text": "<the rewritten reply>"}
        PROMPT
      end

      def tone_instruction = TONES.fetch(hotel.ai_concierge_tone, "Plain and clear. Keep the wording as it is unless the language must change.")
    end
  end
end
