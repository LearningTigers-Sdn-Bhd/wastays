FactoryBot.define do
  factory :prospect_message do
    prospect
    # A message with no thread is no longer a thing the column allows, so the
    # factory builds one for the prospect it was asked for rather than a
    # stranger's -- the inbox reads the two together.
    conversation { association :conversation, hotel: prospect.hotel, prospect: prospect }
    direction { "inbound" }
    body { "Hello there" }
    sent_at { Time.current }
  end
end
