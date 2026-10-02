# frozen_string_literal: true

module Ezee
  # Finds the travel agent behind a reservation that has no Business Source.
  #
  # Staff often leave Business Source empty and type the agency into the guest
  # field instead, with the agent's contact in brackets: "PERFECT HOLIDAY
  # (SABRINA)", "DREAMY ISLAND ( MOON )". Read as a guest, those become a person
  # named after a company and the agency's ledger never sees the booking.
  #
  # Only rows with no Business Source are looked at, and only two shapes count:
  #
  # - "NAME (CONTACT)": the part before the bracket is the agency.
  # - a name that is, or is the start of, an agency the same file names in
  #   Business Source ("GOOD EARTH TRAVEL" for "GOOD EARTH TRAVEL AND TOUR SDN.
  #   BHD.", or a person who is also a Business Source on other rows).
  #
  # An agency written differently from its Business Source spelling is matched to
  # that spelling, so one company is one account. The match works on words: a
  # sub-sequence of the known name, with Holiday / Holidays / Vacation counted as
  # one word (Perfect Holidays and Perfect Vacation Sdn. Bhd. are the same
  # company). If two known agencies fit equally the name is not guessed at: the
  # row gets its own agency, spelled as typed.
  #
  # Mutates the rows it recognises and leaves every other row exactly as it was.
  class AgencyFromGuest
    BRACKETED = /\A(?<agency>[^()]+?)\s*\(\s*(?<contact>[^()]*?)\s*\)\s*\z/
    LEGAL_SUFFIX = /\b(SDN|BHD|SND|LTD|CO|LIMITED|PTE)\b/
    SAME_WORD = { "HOLIDAYS" => "HOLIDAY", "VACATION" => "HOLIDAY", "VACATIONS" => "HOLIDAY" }.freeze

    def self.call(rows) = new(rows).call

    def initialize(rows)
      @rows = rows
    end

    def call
      known = @rows.filter_map(&:agency_name).uniq
      @rows.each do |row|
        next unless unlabeled?(row)

        agency, contact = agency_in(row.guest_name, known)
        next if agency.nil?

        row.agency_name = agency
        row.source = "Travel Agent"
        row.source_key = "travel_agent"
        row.internal_note = note_for(row, agency, contact)
      end
      @rows
    end

    private

    def unlabeled?(row) = row.agency_name.blank? && row.source == "Unlabeled"

    # => [agency, contact] or nil
    def agency_in(guest_name, known)
      name = guest_name.to_s.squish
      match = name.match(BRACKETED)
      candidate = match ? match[:agency].squish : name
      contact = match && match[:contact].presence

      known_name = known_agency_for(candidate, known)
      return [ known_name, contact ] if known_name
      return [ candidate, contact ] if match && candidate.present?

      nil
    end

    # The one known agency this name is, or starts, or sits inside. Two that fit
    # equally is an ambiguity, not a match.
    def known_agency_for(candidate, known)
      words = words_of(candidate)
      return nil if words.empty?

      fits = known.select { |name| contains?(words_of(name), words) }
      fits.one? ? fits.first : nil
    end

    def contains?(haystack, needle)
      haystack.each_cons(needle.size).any? { |run| run == needle }
    end

    def words_of(name)
      name.to_s.upcase.gsub(LEGAL_SUFFIX, " ").scan(/[A-Z0-9]+/).map { |word| SAME_WORD.fetch(word, word) }
    end

    def note_for(row, agency, contact)
      spelled = row.guest_name.to_s.squish
      parts = [ "Agent booking: agency taken from the guest field (#{spelled}) as #{agency}." ]
      parts << "Contact: #{contact}." if contact.present?
      # The caller's own note still applies (a stripped title, a balance gap),
      # but "unlabeled agent booking" is no longer the whole story.
      kept = row.internal_note.to_s.sub(ReservationCsvParser::UNLABELED_NOTE, "").squish
      (parts + [ kept.presence ]).compact.join(" ")
    end
  end
end
