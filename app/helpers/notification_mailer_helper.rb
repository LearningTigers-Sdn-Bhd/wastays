# frozen_string_literal: true

# A delivery's payload is a record of what was sent, so its dates are stored as
# ISO strings rather than as objects that would re-render against today's
# settings. They are parsed back for display here rather than in each template,
# where the existing mails each carry their own inline `rescue`.
module NotificationMailerHelper
  def format_payload_date(value)
    return if value.blank?

    Date.parse(value.to_s).strftime("%d %b %Y")
  rescue Date::Error
    value
  end
end
