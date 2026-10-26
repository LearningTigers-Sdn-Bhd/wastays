# frozen_string_literal: true

module Guests
  # Whether new details describe someone other than the person a guest profile
  # belongs to.
  #
  # A profile holds one person's stays and ID documents and is shared across
  # hotels. Saving another person's name and IC over it files their stays under
  # the wrong person, so callers refuse that. An ID number decides when both
  # sides have one of the same kind (a passport number says nothing against a
  # MyKad, the same person can hold both). Otherwise the names decide: more than half of the shorter
  # name's words must appear in the other, a typo within a word allowed.
  # "ROLLEAND MARINUS" and "ROLLEANNY MARINUS" are one person; "EZZA" and
  # "IBRAHIM BIN AYUB" are two. Particles such as BIN and BINTI are not
  # evidence. Blank details never make a different person.
  class DifferentPerson
    PARTICLES = %w[bin binti binte bt bte b anak ak a l p s o d al ap].freeze

    def self.call(guest, name:, document_type: nil, government_id: nil, passport_number: nil)
      new(guest, name:, document_type:, government_id:, passport_number:).call
    end

    def initialize(guest, name:, document_type:, government_id:, passport_number:)
      @guest = guest
      @name = name
      @document_numbers = { passport_number: }
      @document_numbers[:government_id] = government_id if same_document_type?(document_type)
    end

    def call
      verdict = document_verdict
      verdict.nil? ? different_names? : verdict
    end

    private

    def document_verdict
      @document_numbers.each do |attribute, given|
        given = normalize(given)
        stored = normalize(@guest.safely_read_encrypted(attribute))
        return given != stored if given.present? && stored.present?
      end

      nil
    end

    def same_document_type?(document_type)
      type = GuestIdentityDocuments::NormalizeType.call(value: document_type, country: @guest.country)
      type.blank? || @guest.document_type.blank? || type == @guest.document_type
    end

    def different_names?
      shorter, longer = [ words(@guest.name), words(@name) ].sort_by(&:size)
      return false if shorter.empty?

      shared = shorter.count { |word| longer.any? { |other| same_word?(word, other) } }
      shared * 2 <= shorter.size
    end

    def words(name)
      (ChannelManagers::MatchChannelGuest.name_tokens(name) - PARTICLES).uniq
    end

    def same_word?(one, other)
      return true if one == other
      return false if [ one.length, other.length ].min < 3

      DidYouMean::Levenshtein.distance(one, other) <= ([ one.length, other.length ].min >= 6 ? 2 : 1)
    end

    def normalize(number)
      number.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
  end
end
