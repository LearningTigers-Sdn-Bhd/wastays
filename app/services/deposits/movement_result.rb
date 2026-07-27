# frozen_string_literal: true

module Deposits
  MovementResult = ApplicationResult.define(:deposit, :movement, :transaction)
end
