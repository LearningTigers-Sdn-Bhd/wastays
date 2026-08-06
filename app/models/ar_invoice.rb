# frozen_string_literal: true

# Compatibility name retained for one expand-contract release. New code should
# use Receivable; both classes intentionally address the same legacy table and
# preserve existing route/payment-allocation IDs.
class ArInvoice < Receivable
end
