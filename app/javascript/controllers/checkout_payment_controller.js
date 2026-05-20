import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "submitButton", "paymentIdField", "orderIdField", "signatureField", "nameField", "emailField", "phoneField" ]
  static values = {
    sessionUrl: String,
    hotelName: String,
    quoteToken: String,
    ready: Boolean
  }

  initialize() {
    this.submittingToServer = false
  }

  submit(event) {
    if (this.submittingToServer) return
    if (!this.readyValue) return

    event.preventDefault()
    this.submitButtonTarget.disabled = true
    this.originalLabel = this.submitButtonTarget.value
    this.submitButtonTarget.value = "Opening secure checkout..."

    const formData = new FormData(this.element)

    fetch(this.sessionUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: formData
    })
      .then(response => {
        if (!response.ok) {
          return response.json().then(err => { throw new Error(err.error || "Unable to initialize checkout.") })
        }
        return response.json()
      })
      .then(session => {
        if (session.checkout_url) {
          window.location.href = session.checkout_url
          return
        }

        if (!session.key_id || !session.order_id) {
          throw new Error("Unsupported checkout session payload.")
        }
        if (!window.Razorpay) {
          throw new Error("Payment service is temporarily unavailable. Please refresh and try again.")
        }

        this.openRazorpay(session)
      })
      .catch(error => {
        alert(error.message || "Unable to start payment. Please try again.")
        this.submitButtonTarget.disabled = false
        this.submitButtonTarget.value = this.originalLabel
      })
  }

  openRazorpay(session) {
    const options = {
      key: session.key_id,
      amount: session.amount,
      currency: session.currency,
      name: this.hotelNameValue,
      description: session.description,
      order_id: session.order_id,
      callback_url: session.callback_url,
      redirect: true,
      handler: (paymentResponse) => {
        this.paymentIdFieldTarget.value = paymentResponse.razorpay_payment_id || ""
        this.orderIdFieldTarget.value = paymentResponse.razorpay_order_id || ""
        this.signatureFieldTarget.value = paymentResponse.razorpay_signature || ""
        this.submittingToServer = true
        this.element.requestSubmit()
      },
      prefill: {
        name: this.hasNameFieldTarget ? this.nameFieldTarget.value : "",
        email: this.hasEmailFieldTarget ? this.emailFieldTarget.value : "",
        contact: this.hasPhoneFieldTarget ? this.phoneFieldTarget.value : ""
      },
      notes: {
        quote_token: this.quoteTokenValue
      },
      theme: {
        color: "#d32f2f"
      }
    }

    const razorpay = new window.Razorpay(options)
    razorpay.on("payment.failed", () => {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.value = this.originalLabel
    })
    razorpay.open()
  }
}
