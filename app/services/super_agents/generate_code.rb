# frozen_string_literal: true

module SuperAgents
  # Makes a unique 6-character code for a super agent's invite link.
  class GenerateCode
    # Letters and digits that cannot be misread for each other (no 0/O, 1/I).
    CHARACTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze
    LENGTH = 6

    def self.call
      loop do
        code = Array.new(LENGTH) { CHARACTERS[SecureRandom.random_number(CHARACTERS.length)] }.join
        return code unless User.exists?(agent_code: code)
      end
    end
  end
end
