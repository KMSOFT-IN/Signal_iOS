//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public struct RegistrationPhoneNumberDiscoverabilityState: Equatable {
    let e164: String
}

protocol RegistrationPhoneNumberDiscoverabilityPresenter: AnyObject {
    func setPhoneNumberDiscoverability(_ isDiscoverable: Bool)
}

class RegistrationPhoneNumberDiscoverabilityViewController: OWSViewController {
    private let state: RegistrationPhoneNumberDiscoverabilityState
    private weak var presenter: RegistrationPhoneNumberDiscoverabilityPresenter?

    public init(
        state: RegistrationPhoneNumberDiscoverabilityState,
        presenter: RegistrationPhoneNumberDiscoverabilityPresenter
    ) {
        self.state = state
        self.presenter = presenter
        super.init()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: State

    private var isDiscoverableByPhoneNumber: Bool = true {
        didSet { render() }
    }

    // MARK: Rendering

    private lazy var nextBarButton = UIBarButtonItem(
        title: CommonStrings.nextButton,
        style: .done,
        target: self,
        action: #selector(didTapNext),
        accessibilityIdentifier: "registration.phoneNumberDiscoverability.nextButton"
    )

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_DISCOVERABILITY_TITLE",
            comment: "Title of the 'onboarding phone number discoverability' view."
        ))
        result.accessibilityIdentifier = "registration.phoneNumberDiscoverability.titleLabel"
        return result
    }()

    private lazy var explanationLabel: UILabel = {
        let formattedPhoneNumber = state.e164.e164FormattedAsPhoneNumberWithoutBreaks
        let explanationTextFormat = OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_DISCOVERABILITY_EXPLANATION_FORMAT",
            comment: "Explanation of the 'onboarding phone number discoverability' view. Embeds {user phone number}"
        )

        let result = UILabel.explanationLabelForRegistration(
            text: String(format: explanationTextFormat, formattedPhoneNumber)
        )
        result.accessibilityIdentifier = "registration.phoneNumberDiscoverability.explanationLabel"

        return result
    }()

    private lazy var everybodyButton: ButtonRow = {
        let result = ButtonRow(title: PhoneNumberDiscoverability.nameForDiscoverability(true))
        result.handler = { [weak self] _ in
            self?.isDiscoverableByPhoneNumber = true
        }
        return result
    }()

    private lazy var nobodyButton: ButtonRow = {
        let result = ButtonRow(title: PhoneNumberDiscoverability.nameForDiscoverability(false))
        result.handler = { [weak self] _ in
            self?.isDiscoverableByPhoneNumber = false
        }
        return result
    }()

    private lazy var selectionDescriptionLabel: UILabel = {
        let result = UILabel()
        result.font = .ows_dynamicTypeCaption1Clamped
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()
        initialRender()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        navigationItem.rightBarButtonItem = nextBarButton

        let descriptionLabelContainer = UIView()
        descriptionLabelContainer.addSubview(selectionDescriptionLabel)
        selectionDescriptionLabel.autoPinEdgesToSuperviewMargins()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            .spacer(withHeight: 16),
            explanationLabel,
            .spacer(withHeight: 24),
            everybodyButton,
            nobodyButton,
            .spacer(withHeight: 16),
            descriptionLabelContainer,
            .vStretchingSpacer(minHeight: 16)
        ])
        stackView.axis = .vertical
        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        render()
    }

    private func render() {
        everybodyButton.isSelected = isDiscoverableByPhoneNumber
        nobodyButton.isSelected = !isDiscoverableByPhoneNumber

        selectionDescriptionLabel.text = PhoneNumberDiscoverability.descriptionForDiscoverability(isDiscoverableByPhoneNumber)

        view.backgroundColor = Theme.backgroundColor
        nextBarButton.tintColor = Theme.accentBlueColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationLabel.textColor = .colorForRegistrationExplanationLabel
        selectionDescriptionLabel.textColor = .colorForRegistrationExplanationLabel
    }

    // MARK: Events

    @objc
    private func didTapNext() {
        Logger.info("")

        presenter?.setPhoneNumberDiscoverability(isDiscoverableByPhoneNumber)
    }
}

// MARK: - ButtonRow

private class ButtonRow: UIButton {
    var handler: ((ButtonRow) -> Void)?

    private let selectedImageView = UIImageView()

    static let vInset: CGFloat = 11
    static var hInset: CGFloat { Deprecated_RegistrationPhoneNumberDiscoverabilityViewController.hInset }

    override var isSelected: Bool {
        didSet {
            selectedImageView.isHidden = !isSelected
        }
    }

    init(title: String) {
        super.init(frame: .zero)

        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        setBackgroundImage(UIImage(color: Theme.cellSelectedColor), for: .highlighted)
        setBackgroundImage(UIImage(color: Theme.backgroundColor), for: .normal)

        let titleLabel = UILabel()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = .ows_dynamicTypeBodyClamped
        titleLabel.text = title

        selectedImageView.isHidden = true
        selectedImageView.setTemplateImageName(Theme.iconName(.accessoryCheckmark), tintColor: Theme.primaryIconColor)
        selectedImageView.contentMode = .scaleAspectFit
        selectedImageView.autoSetDimension(.width, toSize: 24)

        let stackView = UIStackView(arrangedSubviews: [titleLabel, .hStretchingSpacer(), selectedImageView])
        stackView.isUserInteractionEnabled = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(
            top: Self.vInset,
            leading: Self.hInset,
            bottom: Self.vInset,
            trailing: Self.hInset
        )

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoSetDimension(.height, toSize: 44, relation: .greaterThanOrEqual)

        let divider = UIView()
        divider.backgroundColor = Theme.middleGrayColor
        addSubview(divider)
        divider.autoSetDimension(.height, toSize: CGHairlineWidth())
        divider.autoPinEdge(toSuperviewEdge: .trailing)
        divider.autoPinEdge(toSuperviewEdge: .bottom)
        divider.autoPinEdge(toSuperviewEdge: .leading, withInset: Self.hInset)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func didTap() {
        handler?(self)
    }
}
