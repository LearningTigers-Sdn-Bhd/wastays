class SystemMailer < ApplicationMailer
  def observability_test(email)
    mail(to: email, subject: "Observation Deck - Test Email") do |format|
      format.html { render html: "<h1>Test Successful</h1><p>The Observation Deck is now monitoring outgoing mail.</p>".html_safe }
    end
  end
end
