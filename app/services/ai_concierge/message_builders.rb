module AiConcierge
  # The sentence the assistant sends when nothing else can be rendered: no
  # reply type any builder recognises, or a turn that fell over.
  #
  # It lives on the namespace rather than in a class because the three places
  # that reach for it -- the messenger's last resort, the loop's fallback
  # outcome and the booking orchestrator's -- are not builders and never were.
  module MessageBuilders
    DEFAULT_MESSAGE = "I'm unable to answer that right now. Please contact the hotel team for assistance.".freeze
  end
end
