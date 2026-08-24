# frozen_string_literal: true

# Lets an outgoing webhook say whose events it wants, and which.
#
# Both columns are deliberately "unset means everything", because that is what
# every endpoint configured before this migration already was: a single relay
# serving every hotel. Requiring a hotel here would silently stop those relays
# on deploy, and a webhook that stops is a guest who never hears back.
#
# Nullable `hotel_id` is therefore a real state, not a missing value -- it says
# "this endpoint serves the whole platform". Pinning one to a hotel is what the
# per-hotel WhatsApp relays need, and until now was impossible to express.
class ScopeWebhookEndpointsToHotelsAndEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :webhook_endpoints, :hotel, null: true, foreign_key: true
    add_column :webhook_endpoints, :event_types, :text, default: [], null: false, array: true
  end
end
