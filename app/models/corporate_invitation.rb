# frozen_string_literal: true

class CorporateInvitation < Invitation
  store_accessor :metadata,
    :relationship_type,
    :direct_bill_enabled,
    :credit_limit,
    :credit_currency,
    :payment_terms_days

  default_scope { corporate }

  before_validation { self.kind = "corporate" }
  before_validation :default_credit_currency

  validates :relationship_type, inclusion: { in: %w[standard direct_bill] }
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :payment_terms_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :credit_currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }

  def direct_bill_enabled
    ActiveModel::Type::Boolean.new.cast(super)
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
end
