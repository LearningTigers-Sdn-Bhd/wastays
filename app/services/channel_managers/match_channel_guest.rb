# frozen_string_literal: true

module ChannelManagers
  # Finds the guest profile an OTA booking belongs to, or nothing.
  #
  # An OTA booking describes two people: the booker, whose email and phone it
  # carries, and the guest staying, whose name the profile is filed under.
  # They are often different (an agent, a company, a parent). Profiles are
  # shared across properties and hold ID documents and stay history, so a
  # wrong match puts one person's identity in front of another's check-in. A
  # missed match only costs a duplicate staff can merge. So this matches only
  # on evidence that belongs to the guest staying:
  #
  # 1. A government ID, which is the person's own.
  # 2. An email or phone, but only when the booker is the guest staying (so the
  #    contact is theirs) and the profile carries the same name.
  class MatchChannelGuest
    def self.call(guest_details) = new(guest_details).call

    # Same person by name: case, accents, punctuation, spacing and word order
    # aside. "TAN, Alice" and "alice tan" match; "Alice" and "Alice Tan" don't.
    def self.same_name?(one, other)
      tokens = name_tokens(one)
      tokens.any? && tokens == name_tokens(other)
    end

    # No word in common, so not a respelling of the same name.
    def self.different_people?(one, other)
      (name_tokens(one) & name_tokens(other)).empty?
    end

    def self.name_tokens(name)
      name.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
        .gsub(/[^\p{L}\p{N}\s]/, " ").split.sort
    end

    def initialize(guest_details)
      @details = guest_details.to_h.symbolize_keys
    end

    def call
      by_government_id || by_contact
    end

    # Whether the email and phone on the booking are the staying guest's own.
    def contact_belongs_to_guest?
      booker = @details[:booker_name]
      booker.blank? || self.class.same_name?(booker, @details[:name])
    end

    private

    def by_government_id
      government_id = @details[:government_id].to_s.downcase.strip.presence
      Guest.kept.find_by(government_id:) if government_id
    end

    def by_contact
      return unless contact_belongs_to_guest?

      contact_candidates.find { |guest| self.class.same_name?(guest.name, @details[:name]) }
    end

    def contact_candidates
      email = @details[:email].to_s.downcase.strip.presence
      phone = @details[:phone].to_s.strip.presence
      phone = nil if Guest.placeholder_phone?(phone)

      by_email = email ? Guest.kept.where(email:).order(:created_at).to_a : []
      by_phone = phone ? Guest.kept.where(phone:).order(:created_at).to_a : []
      (by_email + by_phone).uniq
    end
  end
end
