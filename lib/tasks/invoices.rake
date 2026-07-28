# frozen_string_literal: true

namespace :invoices do
  desc "Idempotently reconcile legacy folio and AR invoices into unified documents"
  task reconcile_legacy_documents: :environment do
    result = Invoices::ReconcileLegacyDocuments.call
    puts "Settled mapped: #{result.settled_mapped}"
    puts "Direct bill mapped: #{result.direct_bill_mapped}"
    abort result.errors.join("\n") if result.errors.any?
  end
end
