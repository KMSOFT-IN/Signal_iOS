//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - RegistrationVerificationValidationError

public enum RegistrationVerificationValidationError: Equatable {
    case invalidVerificationCode(invalidCode: String)
    // These three errors are what happens when we try and
    // take the three respective actions but are rejected
    // with a timeout. The State should have timeout information.
    case smsResendTimeout
    case voiceResendTimeout
    case submitCodeTimeout
}

// MARK: - RegistrationVerificationState

public struct RegistrationVerificationState: Equatable {
    let e164: String
    let nextSMSDate: Date?
    let nextCallDate: Date?
    // TODO[Registration]: use this state to render a countdown.
    let nextVerificationAttemptDate: Date
    // TODO[Registration]: use this state to render error UI.
    let validationError: RegistrationVerificationValidationError?
}

// MARK: - RegistrationVerificationPresenter

protocol RegistrationVerificationPresenter: AnyObject {
    func returnToPhoneNumberEntry()
    func requestSMSCode()
    func requestVoiceCode()
    func submitVerificationCode(_ code: String)
}

// MARK: - RegistrationVerificationViewController

class RegistrationVerificationViewController: OWSViewController {
    public init(
        state: RegistrationVerificationState,
        presenter: RegistrationVerificationPresenter
    ) {
        self.state = state
        self.presenter = presenter

        super.init()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    public func updateState(_ state: RegistrationVerificationState) {
        self.state = state
    }

    deinit {
        nowTimer?.invalidate()
        nowTimer = nil
    }

    // MARK: Internal state

    private var state: RegistrationVerificationState {
        didSet { render() }
    }

    private weak var presenter: RegistrationVerificationPresenter?

    private var now = Date() {
        didSet { render() }
    }
    private var nowTimer: Timer?

    private var canRequestSMSCode: Bool {
        guard let nextDate = state.nextSMSDate else { return false }
        return nextDate <= now
    }

    private var canRequestVoiceCode: Bool {
        guard let nextDate = state.nextCallDate else { return false }
        return nextDate <= now
    }

    // MARK: Rendering

    private func button(
        title: String = "",
        selector: Selector,
        accessibilityIdentifierSuffix: String
    ) -> OWSFlatButton {
        let result = OWSFlatButton.button(
            title: title,
            font: UIFont.ows_dynamicTypeSubheadlineClamped,
            titleColor: .clear, // This should be overwritten in `render`.
            backgroundColor: .clear,
            target: self,
            selector: selector
        )
        result.enableMultilineLabel()
        result.contentEdgeInsets = UIEdgeInsets(margin: 12)
        result.accessibilityIdentifier = "registration.verification.\(accessibilityIdentifierSuffix)"
        return result
    }

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_VERIFICATION_TITLE_LABEL",
            comment: "Title label for the onboarding verification page"
        ))
        result.accessibilityIdentifier = "registration.verification.titleLabel"
        return result
    }()

    private lazy var explanationLabel: UILabel = {
        let format = OWSLocalizedString(
            "ONBOARDING_VERIFICATION_TITLE_DEFAULT_FORMAT",
            comment: "Format for the title of the 'onboarding verification' view. Embeds {{the user's phone number}}."
        )
        let text = String(format: format, state.e164.e164FormattedAsPhoneNumberWithoutBreaks)

        let result = UILabel.explanationLabelForRegistration(text: text)
        result.accessibilityIdentifier = "registration.verification.explanationLabel"
        return result
    }()

    private lazy var wrongNumberButton: OWSFlatButton = button(
        title: OWSLocalizedString(
            "ONBOARDING_VERIFICATION_BACK_LINK",
            comment: "Label for the link that lets users change their phone number in the onboarding views."
        ),
        selector: #selector(didTapWrongNumberButton),
        accessibilityIdentifierSuffix: "wrongNumberButton"
    )

    private lazy var verificationCodeView: RegistrationVerificationCodeView = {
        let result = RegistrationVerificationCodeView()
        result.delegate = self
        return result
    }()

    private lazy var resendSMSCodeButton: OWSFlatButton = button(
        selector: #selector(didTapResendSMSCode),
        accessibilityIdentifierSuffix: "resendSMSCodeButton"
    )

    private lazy var requestVoiceCodeButton: OWSFlatButton = button(
        selector: #selector(didTapSendVoiceCode),
        accessibilityIdentifierSuffix: "requestVoiceCodeButton"
    )

    public override func viewDidLoad() {
        super.viewDidLoad()

        initialRender()

        // We don't need this timer in all cases but it's simpler to start it in all cases.
        nowTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.now = Date()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        verificationCodeView.becomeFirstResponder()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        let stackView = UIStackView()

        stackView.axis = .vertical
        stackView.spacing = 12
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        stackView.addArrangedSubview(titleLabel)

        stackView.addArrangedSubview(explanationLabel)

        stackView.addArrangedSubview(wrongNumberButton)
        stackView.setCustomSpacing(24, after: wrongNumberButton)

        stackView.addArrangedSubview(verificationCodeView)

        // TODO[Registration]: If the user has tried several times, show a "need help" button.

        stackView.addArrangedSubview(UIView.vStretchingSpacer(minHeight: 12))

        let resendButtonsContainer = UIStackView(arrangedSubviews: [
            resendSMSCodeButton,
            requestVoiceCodeButton
        ])
        resendButtonsContainer.axis = .horizontal
        resendButtonsContainer.distribution = .fillEqually
        stackView.addArrangedSubview(resendButtonsContainer)

        render()
    }

    private func render() {
        renderResendButton(
            button: resendSMSCodeButton,
            date: state.nextSMSDate,
            // TODO: This copy is ambiguous if you request a voice code. Does "resend code" mean
            // that you'll get a new SMS code or a new voice code? We should update the wording to
            // make it clearer that it's an SMS code.
            enabledString: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_RESEND_CODE_BUTTON",
                comment: "Label for button to resend SMS verification code."
            ),
            countdownFormat: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_RESEND_CODE_COUNTDOWN_FORMAT",
                comment: "Format string for button counting down time until SMS code can be resent. Embeds {{time remaining}}."
            )
        )
        renderResendButton(
            button: requestVoiceCodeButton,
            date: state.nextCallDate,
            enabledString: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_CALL_ME_BUTTON",
                comment: "Label for button to perform verification with a phone call."
            ),
            countdownFormat: OWSLocalizedString(
                "ONBOARDING_VERIFICATION_CALL_ME_COUNTDOWN_FORMAT",
                comment: "Format string for button counting down time until phone call verification can be performed. Embeds {{time remaining}}."
            )
        )

        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationLabel.textColor = .colorForRegistrationExplanationLabel
        wrongNumberButton.setTitleColor(Theme.accentBlueColor)
        // TODO: Update colors of `verificationCodeView`, which is relevant if the theme changes.
    }

    private lazy var retryAfterFormatter: DateFormatter = {
        let result = DateFormatter()
        result.dateFormat = "m:ss"
        result.timeZone = TimeZone(identifier: "UTC")!
        return result
    }()

    private func renderResendButton(
        button: OWSFlatButton,
        date: Date?,
        enabledString: String,
        countdownFormat: String
    ) {
        guard let date else {
            button.alpha = 0
            button.setEnabled(false)
            return
        }

        button.alpha = 1

        if date <= now {
            button.setEnabled(true)
            button.setTitle(title: enabledString, titleColor: Theme.accentBlueColor)
        } else {
            button.setEnabled(false)
            button.setTitle(
                title: {
                    let timeRemaining = max(date.timeIntervalSince(now), 0)
                    let durationString = retryAfterFormatter.string(from: Date(timeIntervalSinceReferenceDate: timeRemaining))
                    return String(format: countdownFormat, durationString)
                }(),
                titleColor: Theme.secondaryTextAndIconColor
            )
        }
    }

    // MARK: Events

    @objc
    private func didTapWrongNumberButton() {
        Logger.info("")

        presenter?.returnToPhoneNumberEntry()
    }

    @objc
    private func didTapResendSMSCode() {
        Logger.info("")

        guard canRequestSMSCode else { return }

        presentActionSheet(.forRegistrationVerificationConfirmation(
            mode: .sms,
            e164: state.e164,
            didConfirm: { [weak self] in self?.presenter?.requestSMSCode() },
            didRequestEdit: { [weak self] in self?.presenter?.returnToPhoneNumberEntry() }
        ))
    }

    @objc
    private func didTapSendVoiceCode() {
        Logger.info("")

        guard canRequestVoiceCode else { return }

        presentActionSheet(.forRegistrationVerificationConfirmation(
            mode: .voice,
            e164: state.e164,
            didConfirm: { [weak self] in self?.presenter?.requestVoiceCode() },
            didRequestEdit: { [weak self] in self?.presenter?.returnToPhoneNumberEntry() }
        ))
    }
}

// MARK: - RegistrationVerificationCodeViewDelegate

extension RegistrationVerificationViewController: RegistrationVerificationCodeViewDelegate {
    func codeViewDidChange() {
        if verificationCodeView.isComplete {
            Logger.info("Submitting verification code")
            verificationCodeView.resignFirstResponder()
            presenter?.submitVerificationCode(verificationCodeView.verificationCode)
        }
    }
}
