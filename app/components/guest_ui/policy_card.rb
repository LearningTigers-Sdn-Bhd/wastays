# frozen_string_literal: true

module GuestUI
  # One policy a guest reads: house rules, room terms, the cost of a change.
  # The frame is a GuideCard; this card owns the body.
  #
  # Staff write one rule a line, so each line becomes a list item a guest can
  # scan. A policy of one line stays a sentence. Terms are the other shape: a
  # named change and its charge, with the note staff wrote under it.
  #
  # Always open. The Policies page holds nothing else, so a closed card would
  # only add a tap.
  class PolicyCard < GuestUI::BaseComponent
    Term = Data.define(:label, :value, :note)

    def initialize(title:, icon: "file-text", body: nil, terms: [], class: nil, **attributes)
      @title = title
      @icon = icon
      @rules = body.to_s.lines.map { |line| line.strip.sub(/\A[•\-*]\s+/, "") }.compact_blank
      @terms = terms.map { |term| term.is_a?(Term) ? term : Term.new(*term) }
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def render? = @rules.any? || @terms.any?

    private

    attr_reader :title, :icon, :rules, :terms

    def card_attributes
      @attributes.merge(class: tw_merge("guest-policy", @class))
    end
  end
end
