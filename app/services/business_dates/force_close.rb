# frozen_string_literal: true

module BusinessDates
  class ForceClose
    def self.call!(**kwargs)
      CloseAndOpenNext.call!(**kwargs, force: true)
    end
  end
end
