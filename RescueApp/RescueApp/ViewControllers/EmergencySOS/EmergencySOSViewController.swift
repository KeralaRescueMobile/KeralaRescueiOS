//
/*
EmergencySOSViewController.swift
Created on: 12/9/18

Abstract:
 self descriptive

*/

import UIKit
import AVFoundation
import CoreLocation
import MediaPlayer
import MessageUI

final class EmergencySOSViewController: UIViewController, RANavigationProtocol {
    
    // MARK: Properties
    /// IBOUTLETS
    @IBOutlet private weak var tableView: UITableView!
    /// PRIVATE
    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer!
    private var contacts = [EmergencyContact]()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocationCoordinate2D?
    private let toolsSections = ["Flashlight", "Strobe Light", "Alarm"]
    private let safetySections = [
        [C.SAFETY_BUTTON_CONFIG.TITLE_KEY: "MARK AS SAFE", C.SAFETY_BUTTON_CONFIG.COLOR_KEY: RAColorSet.SAFE_GREEN],
        [C.SAFETY_BUTTON_CONFIG.TITLE_KEY: "NEED HELP", C.SAFETY_BUTTON_CONFIG.COLOR_KEY: RAColorSet.WARNING_RED]]
    private struct C {
        static let TITLE = "Emergency/SOS"
        struct CELL_ID {
            static let WITH_SWITCH = "SOSCellWithSwitch"
            static let WITH_BUTTON = "SOSCellWithButton"
            static let BLANK = "SOSCellBlank"
        }
        struct SAFETY_BUTTON_CONFIG {
            static let TITLE_KEY = "title"
            static let COLOR_KEY = "color"
        }
        static let SEGUE_TO_SETTINGS = "segueToSettings"
        static let STROBE_TIME_INTERVAL = 0.2
    }

    // MARK: View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureUIFromViewDidLoad()
        initAudioPlayer()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchContacts()
        updateLocationStatus()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: Button Actions
    
    func onToggleFlashlight() {
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            do {
                try device.lockForConfiguration()
                let torchOn = device.torchMode
                try device.setTorchModeOn(level: 1.0)
                device.torchMode = torchOn == .off ? .on : .off
                device.unlockForConfiguration()
            } catch {
                print("error")
            }
        }
    }
    
    func turnOffFlashlight() {
        if let device = AVCaptureDevice.default(for: .video), device.hasTorch {
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            } catch {
                print("error")
            }
        }
    }
    
    func onToggleStrobeLight() {
        if timer != nil {
            timer?.invalidate()
            timer = nil
            turnOffFlashlight()
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: C.STROBE_TIME_INTERVAL, repeats: true) { [weak self] (_) in
                self?.onToggleFlashlight()
            }
            timer?.fire()
        }
    }
    
    func onToggleAlarm() {
        if audioPlayer.isPlaying {
            audioPlayer.stop()
        } else {
            audioPlayer.play()
        }
    }
    
    @objc func onSettingsClick(_ sender: Any) {
        performSegue(withIdentifier: C.SEGUE_TO_SETTINGS, sender: nil)
    }
}

// MARK: Helper Methods

private extension EmergencySOSViewController {
    func configureUIFromViewDidLoad() {
        configureNavigationBar(RAColorSet.RED)
        title = C.TITLE
        navigationItem.backBarButtonItem = UIBarButtonItem()
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "settings"),
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(onSettingsClick(_:)))
    }
    
    func initAudioPlayer() {
        guard let path = Bundle.main.path(forResource: "alarm", ofType: "wav") else {
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            try AVAudioSession.sharedInstance()
                .setCategory(
                    AVAudioSession.Category(
                        rawValue: convertFromAVAudioSessionCategory(AVAudioSession.Category.playback)
                    ),
                    mode: AVAudioSession.Mode.default
            )
        } catch {
            print("Audio Player cannot be initialized")
            return
        }
        audioPlayer.prepareToPlay()
        audioPlayer.volume = 1.0
        audioPlayer.numberOfLoops = -1
    }
    
    func initSystemVolumeHolder(_ parent: UIView) {
        
        guard
            let containerView = parent.viewWithTag(1),
            containerView.viewWithTag(101) == nil
        else {
            return
        }
        print("adding subview")
        containerView.backgroundColor = UIColor.clear
        let mpVolumeView = MPVolumeView(frame: containerView.bounds)
        mpVolumeView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        mpVolumeView.tag = 101
        containerView.addSubview(mpVolumeView)
    }
    
    func updateLocationStatus() {
        guard canShareCurrentLocation() else {
            locationManager.stopUpdatingLocation()
            return
        }
        locationManager.requestWhenInUseAuthorization()
        if CLLocationManager.locationServicesEnabled() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.startUpdatingLocation()
        }
    }
    
    func fetchContacts() {
        contacts = EmergencyContactUtil.fetchContacts()
        tableView.reloadData()
    }
    
    func canShareCurrentLocation() -> Bool {
        return UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.CAN_LOCATION_SHARED)
    }
    
    func sendSMS(messageKey key: String) {
        guard var message = UserDefaults.standard.string(forKey: key) else {
            return
        }
        if canShareCurrentLocation(), let location = currentLocation {
            message = "\(message) Below are the details about my location. " +
                "Google URL: https://www.google.com/maps/?q=\(location.latitude),\(location.longitude) " +
                "Latitude: \(location.latitude) Longitude: \(location.longitude)"
        }
        if (MFMessageComposeViewController.canSendText()) {
            let controller = MFMessageComposeViewController()
            controller.body = message
            controller.recipients = contacts.map { $0.contactNumbers }.flatMap{ $0 }
            controller.messageComposeDelegate = self
            present(controller, animated: true, completion: nil)
        }
    }
}

extension EmergencySOSViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var rowCount = 0
        if section == 0 {
            rowCount = toolsSections.count + 1 /* SLIDER */
        } else if section == 1 {
            rowCount = safetySections.count
        }
        return rowCount
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell!
        switch indexPath.section {
        case 0:
            if indexPath.row == toolsSections.count {
                // SLIDER
                cell = tableView.dequeueReusableCell(withIdentifier: C.CELL_ID.BLANK)
                initSystemVolumeHolder(cell.contentView)
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: C.CELL_ID.WITH_SWITCH)
                let label = cell.viewWithTag(1) as! UILabel
                label.text = toolsSections[indexPath.row]
            }
        case 1:
            cell = tableView.dequeueReusableCell(withIdentifier: C.CELL_ID.WITH_BUTTON)
            let label = cell.viewWithTag(1) as! UILabel
            let safetyConfig = safetySections[indexPath.row]
            label.text = safetyConfig[C.SAFETY_BUTTON_CONFIG.TITLE_KEY] as? String
            label.backgroundColor = safetyConfig[C.SAFETY_BUTTON_CONFIG.COLOR_KEY] as? UIColor
            label.isEnabled = contacts.count > 0
        default:
            abort()
        }
        cell.selectionStyle = .none
        return cell!
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        var title: String!
        if section == 0 {
            title = "Emergency Tools"
        } else if section == 1 {
            title = "Safety Actions"
            if contacts.count == 0 {
                title = "\(title!) (Currently inactive. Please click the settings button and add Recipients)"
            }
        }
        return title
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case 0:
            if indexPath.row == toolsSections.count {
                return
            }
            let cell = tableView.cellForRow(at: indexPath)
            let toggleSwitch = cell?.viewWithTag(2) as! UISwitch
            toggleSwitch.isOn = !toggleSwitch.isOn
            switch indexPath.row {
            case 0:
                onToggleFlashlight()
            case 1:
                onToggleStrobeLight()
            case 2:
                onToggleAlarm()
            default:
                abort()
            }
        case 1:
            if contacts.count == 0 {
                return
            }
            switch indexPath.row {
            case 0:
                sendSMS(messageKey: Constants.UserDefaultsKeys.MARK_AS_SAFE_MESSAGE)
            case 1:
                sendSMS(messageKey: Constants.UserDefaultsKeys.DANGER_NEED_HELP_MESSAGE)
            default:
                abort()
            }
        default:
            abort()
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        var height: CGFloat = 44.0
        if indexPath.section == 1 {
            height = 64
        } else if indexPath.section == 0 && indexPath.row == toolsSections.count {
            height = 64
        }
        return height
    }
}

extension EmergencySOSViewController: MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                      didFinishWith result: MessageComposeResult) {
        dismiss(animated: true, completion: nil)
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVAudioSessionCategory(_ input: AVAudioSession.Category) -> String {
	return input.rawValue
}

extension EmergencySOSViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let locValue: CLLocationCoordinate2D = manager.location?.coordinate else {
            return
        }
        currentLocation = locValue
    }
}
