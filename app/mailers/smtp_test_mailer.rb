class SmtpTestMailer < ApplicationMailer
  def test_email
    mail(
      to: ENV.fetch("GMAIL_USERNAME"),
      subject: "Mirrorline SMTP Test",
      body: "Gmail SMTP is successfully configured for Mirrorline."
    )
  end
end
