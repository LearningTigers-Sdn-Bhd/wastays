# frozen_string_literal: true

module AiConcierge
  module Matching
    # Which row of a list the guest just named, and whether that is all they
    # said.
    #
    # The catalogue asks to be answered with a number, and guests answer it in
    # whatever words they would have used out loud: "2", "no 2", "2nd", "the
    # second one", "option two". Three places need to read that same answer --
    # the tool that selects the option, the handler that decides whether the
    # guest also named a rate plan, and the normalizer that has to keep the
    # number from being filed as a night, a room or an adult -- so the reading
    # lives here rather than in three vocabularies drifting apart.
    class OptionReference
      ORDINAL_WORDS = {
        "first" => 1, "second" => 2, "third" => 3, "fourth" => 4, "fifth" => 5,
        "sixth" => 6, "seventh" => 7, "eighth" => 8, "ninth" => 9, "tenth" => 10
      }.freeze
      CARDINAL_WORDS = {
        "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5,
        "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10
      }.freeze

      # Words a guest wraps their answer in without changing which row they
      # mean. Deliberately excludes anything that counts something else --
      # "2 rooms" and "2 nights" change the search, not the selection.
      FILLER = %w[
        a an the this that one ones it i id ill my me want wants would like ll lah la
        please just ok okay yes sure go with for take taking pick picked choose
        choosing chose choice number no option row item thanks thank you and then
      ].freeze

      def initialize(message:)
        @normalized = message.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
      end

      # The row the guest named, or nil.
      def number
        return @number if defined?(@number)

        @number = (stated_number || lone_number || spelled_number)&.to_i
      end

      # A row and nothing else. Such a message cannot be about anything but the
      # list: not a rate plan, not a party size, not a length of stay.
      def only_reference?
        return false if number.blank?

        tokens.none? { |token| meaningful?(token) }
      end

      private

      attr_reader :normalized

      def tokens
        @tokens ||= normalized.split
      end

      def meaningful?(token)
        return false if token.match?(/\A\d/)
        return false if FILLER.include?(token)
        return false if ORDINAL_WORDS.key?(token) || CARDINAL_WORDS.key?(token)

        true
      end

      # "no 2" gets a rule of its own because the list is now the only thing a
      # guest can answer by row, and that is how half of them write it. It has
      # to read through words this file has never been given -- "saya mahu no
      # 2" -- where the lone-number rule below, which can only recognise
      # English filler, gives up.
      #
      # It has to end the message, though. "no, 2 adults" is a correction with
      # a count in it, not a row, and everything that says so is in the words
      # after the number.
      def stated_number
        normalized[/\A(\d+)\z/, 1] ||
          normalized[/\b(?:option|number|choice)\s*(\d+)\b/, 1] ||
          normalized[/\bnos?\s*(\d+)\s*\z/, 1] ||
          normalized[/\b(?:choose|chose|picked|pick|take|go with)\s+(?:option\s*)?(\d+)\b/, 1]
      end

      # One number and nothing around it but filler. "2 rooms" and "2 nights"
      # count something else, and "august 3rd" is a date -- so anything that is
      # not filler leaves the message alone, which is also what keeps the
      # ordinal in a date out of this.
      def lone_number
        numbers = tokens.filter_map { |token| token[/\A(\d+)(?:st|nd|rd|th)?\z/, 1] }
        return unless numbers.one?
        return unless tokens.reject { |token| token.match?(/\A\d/) }.all? { |token| FILLER.include?(token) }

        numbers.first
      end

      def spelled_number
        return if tokens.any? { |token| token.match?(/\d/) }

        [ ORDINAL_WORDS, CARDINAL_WORDS ].each do |vocabulary|
          named = tokens.filter_map { |token| vocabulary[token] }
          next unless named.one?
          next unless tokens.reject { |token| vocabulary.key?(token) }.all? { |token| FILLER.include?(token) }

          return named.first
        end

        nil
      end
    end
  end
end
