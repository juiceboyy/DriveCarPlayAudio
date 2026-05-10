import UIKit

final class MainViewController: UIViewController {

    // MARK: - Views
    private let driveIcon     = UIImageView()
    private let titleLabel    = UILabel()
    private let subtitleLabel = UILabel()
    private let authButton    = UIButton(type: .system)
    private let signOutButton = UIButton(type: .system)
    private let toastView     = UIView()
    private let toastLabel    = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupConstraints()
        refreshUI(animated: false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authRequired),
            name: .driveAuthRequired,
            object: nil
        )

        // Propagate player errors to toast
        AudioPlayerService.shared.onError = { [weak self] msg in
            DispatchQueue.main.async { self?.showToast(msg) }
        }
    }

    // MARK: - Actions

    @objc private func didTapAuth() {
        authButton.isEnabled = false
        authButton.configuration?.showsActivityIndicator = true
        Task {
            do {
                try await GoogleAuthService.shared.authenticate()
                await MainActor.run { self.refreshUI(animated: true) }
            } catch {
                await MainActor.run {
                    self.showToast("Aanmelden mislukt: \(error.localizedDescription)")
                    self.refreshUI(animated: true)
                }
            }
        }
    }

    @objc private func didTapSignOut() {
        GoogleAuthService.shared.signOut()
        refreshUI(animated: true)
    }

    @objc private func authRequired() {
        DispatchQueue.main.async { self.didTapAuth() }
    }

    // MARK: - UI state

    private func refreshUI(animated: Bool) {
        let authed = GoogleAuthService.shared.isAuthenticated
        subtitleLabel.text = authed
            ? "Verbonden met Google Drive.\nSluit je iPhone aan op CarPlay om door je muziek te bladeren."
            : "Log in om je Google Drive audio via CarPlay af te spelen."

        authButton.isHidden    = authed
        authButton.isEnabled   = true
        authButton.configuration?.showsActivityIndicator = false
        signOutButton.isHidden = !authed

        if animated {
            UIView.animate(withDuration: 0.3) { self.view.layoutIfNeeded() }
        }
    }

    // MARK: - Toast

    func showToast(_ message: String, duration: TimeInterval = 4.0) {
        toastLabel.text = message
        toastView.isHidden = false
        toastView.alpha    = 0
        UIView.animate(withDuration: 0.3) { self.toastView.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            UIView.animate(withDuration: 0.3, animations: { self.toastView.alpha = 0 }) { _ in
                self.toastView.isHidden = true
            }
        }
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = .systemBackground
        navigationItem.title = "Drive CarPlay Audio"

        // Drive icon
        driveIcon.image       = UIImage(systemName: "music.note.list")
        driveIcon.tintColor   = UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1)
        driveIcon.contentMode = .scaleAspectFit

        // Title
        titleLabel.text          = "Drive CarPlay Audio"
        titleLabel.font          = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center

        // Subtitle
        subtitleLabel.font          = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor     = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center

        // Auth button
        var config             = UIButton.Configuration.filled()
        config.title           = "Aanmelden met Google"
        config.cornerStyle     = .medium
        authButton.configuration = config
        authButton.addTarget(self, action: #selector(didTapAuth), for: .touchUpInside)

        // Sign-out button
        var outConfig          = UIButton.Configuration.plain()
        outConfig.title        = "Uitloggen"
        outConfig.baseForegroundColor = .systemRed
        signOutButton.configuration = outConfig
        signOutButton.addTarget(self, action: #selector(didTapSignOut), for: .touchUpInside)

        // Toast
        toastView.backgroundColor    = UIColor.systemRed.withAlphaComponent(0.9)
        toastView.layer.cornerRadius = 10
        toastView.layer.masksToBounds = true
        toastView.isHidden           = true
        toastLabel.textColor         = .white
        toastLabel.font              = .preferredFont(forTextStyle: .callout)
        toastLabel.numberOfLines     = 0

        [driveIcon, titleLabel, subtitleLabel, authButton, signOutButton, toastView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastView.addSubview(toastLabel)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            driveIcon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            driveIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -120),
            driveIcon.widthAnchor.constraint(equalToConstant: 80),
            driveIcon.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.topAnchor.constraint(equalTo: driveIcon.bottomAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            authButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            authButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            authButton.widthAnchor.constraint(equalToConstant: 260),
            authButton.heightAnchor.constraint(equalToConstant: 50),

            signOutButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            signOutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            toastView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toastView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toastView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            toastLabel.topAnchor.constraint(equalTo: toastView.topAnchor, constant: 12),
            toastLabel.bottomAnchor.constraint(equalTo: toastView.bottomAnchor, constant: -12),
            toastLabel.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 16),
            toastLabel.trailingAnchor.constraint(equalTo: toastView.trailingAnchor, constant: -16),
        ])
    }
}
