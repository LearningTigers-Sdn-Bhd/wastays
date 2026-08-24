FactoryBot.define do
  factory :conversation do
    association :hotel
    prospect { association :prospect, hotel: hotel }
    channel { "web" }
    mode { "bot" }
    status { "open" }
    # A thread exists because somebody wrote on it, and on WhatsApp that
    # timestamp is what decides whether a reply can still be delivered.
    last_guest_message_at { Time.current }

    trait :whatsapp do
      channel { "whatsapp" }
    end

    # Past WhatsApp's 24-hour window: the guest has not written since, so Meta
    # will no longer carry a free-form reply.
    trait :window_lapsed do
      last_guest_message_at { Conversation::REPLY_WINDOW.ago - 1.minute }
    end

    # A WhatsApp thread the guest has never written on, so the window has never
    # opened at all.
    trait :never_heard_from do
      last_guest_message_at { nil }
    end

    trait :with_human do
      mode { "human" }
      association :assigned_user, factory: :user
    end

    trait :closed do
      status { "closed" }
      closed_at { Time.current }
    end
  end
end
