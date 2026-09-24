# frozen_string_literal: true

class CorporateInvitation < Invitation
  # The proposed payment hold rides along as hours, the same canonical unit the
  # relationship stores, so acceptance is a straight copy rather than a second
  # place that has to understand days.
  include AgentPaymentHoldUnit

  store_accessor :metadata,
    :relationship_type,
    :direct_bill_enabled,
    :credit_limit,
    :credit_currency,
    :payment_terms_days,
    :account_type,
    :agent_booking_enabled,
    :agent_payment_hold_hours

  default_scope { corporate }

  before_validation { self.kind = "corporate" }
  before_validation :default_credit_currency
  before_validation :default_account_type
  before_validation :sync_direct_bill_enabled

  validates :relationship_type, inclusion: { in: %w[standard direct_bill] }
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :payment_terms_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :credit_currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :account_type, inclusion: { in: HotelCorporateAccount::ACCOUNT_TYPES }
  validates :agent_payment_hold_hours, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def direct_bill_enabled
    ActiveModel::Type::Boolean.new.cast(super)
  end

  # Reads false rather than nil when the key is absent, which is every
  # invitation written before the permission existed. The relationship column it
  # is copied onto is NOT NULL, and "not recorded" means "not granted".
  def agent_booking_enabled
    ActiveModel::Type::Boolean.new.cast(super) || false
  end
  alias_method :agent_booking_enabled?, :agent_booking_enabled

  def agent_booking_enabled=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  # Stored in a JSON document, so it comes back as whatever was written. The
  # hold is hours everywhere else and has to read back as an integer here too.
  def agent_payment_hold_hours
    value = super
    value.present? ? value.to_i : nil
  end

  def agent_payment_hold_hours=(value)
    super(value.present? ? value.to_i : nil)
  end

  def direct_bill_enabled=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  def credit_limit
    value = super
    value.present? ? BigDecimal(value.to_s) : nil
  end

  def credit_limit=(value)
    super(value.present? ? BigDecimal(value.to_s).to_s("F") : nil)
  rescue ArgumentError
    super(value)
  end

  def payment_terms_days
    value = super
    value.present? ? value.to_i : nil
  end

  def payment_terms_days=(value)
    super(value.present? ? value.to_i : nil)
  end

  def refresh!(invited_by_user:)
    token = rotate_token!
    update!(invited_by_user: invited_by_user)
    token
  end

  private

  def default_credit_currency
    self.credit_currency ||= hotel&.default_currency
  end

  def default_account_type
    self.account_type ||= "company"
  end

  def sync_direct_bill_enabled
    self.direct_bill_enabled = relationship_type == "direct_bill"
  end
end
