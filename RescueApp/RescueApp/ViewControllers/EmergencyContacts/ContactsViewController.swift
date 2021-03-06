//
/*
ContactsViewController.swift
Created on: 23/8/18

Abstract:
 this class will show all the contact lists

*/

import UIKit
import FirebaseDatabase

final class ContactsViewController: UIViewController, RANavigationProtocol {
    
    // MARK: Properties
    /// PRIVATE
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var infoTitlaLabel: UILabel!
    @IBOutlet private weak var dataSourceLabel: UILabel!
    private var contactKeys = [String]()
    private var contactsSections = [String: String]()
    private var contactsSectionDetails = [String: [Contact]]()
    private struct C {
        static let tableCellId = "contactsSectionCell"
        struct FirebaseKeys {
            static let CONTACTS_ROOT = "contacts"
            static let SECTIONS = "sections"
            static let SECTION_DETAILS = "section_details"
        }
        static let segueToList = "segueToContactList"
        static let TITLE = "Emergency Contacts"
        struct SEGUE_PAYLOAD_KEY {
            static let CONTACTS = "contacts"
            static let DEPARTMENT_NAME = "departmentName"
        }
        static let DATA_SOURCE = "Courtesy: disasterlesskerala.org"
    }
    private var ref: DatabaseReference?

    // MARK: View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureUIFromViewDidLoad()
        if ApiClient.isConnected {
            fetchContactsFromFirebase()
        } else {
            fetchContactsFromPLIST()
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == C.segueToList {
            let vc = segue.destination as! ContactsListViewController
            let payload = sender as!  [String: AnyObject]
            vc.departmentName = payload[C.SEGUE_PAYLOAD_KEY.DEPARTMENT_NAME] as? String
            vc.contacts = payload[C.SEGUE_PAYLOAD_KEY.CONTACTS] as! [Contact]
        }
    }
}

// MARK: Helper methods

private extension ContactsViewController {
    func configureUIFromViewDidLoad() {
        title = C.TITLE
        navigationItem.backBarButtonItem = UIBarButtonItem()
        configureNavigationBar(RAColorSet.PURPLE)
        tableView.tableFooterView = UIView()
        dataSourceLabel.text = C.DATA_SOURCE
    }
    
   func fetchContactsFromFirebase() {
        Overlay.shared.show()
        ref = Database.database().reference()
        ref?.child(C.FirebaseKeys.CONTACTS_ROOT).observe(DataEventType.value, with: { [weak self] (snapshot) in
            Overlay.shared.remove()
            let contents = snapshot.value as? [String: AnyObject] ?? [:]
            self?.parseAndPopulateContacts(contents)
        })
    }
    
    func parseAndPopulateContacts(_ contents:  [String: AnyObject]) {
        contactsSections = contents[C.FirebaseKeys.SECTIONS] as? [String: String] ?? [:]
        contactKeys = Array(contactsSections.keys)
        
        let details = contents[C.FirebaseKeys.SECTION_DETAILS] as? [String: AnyObject] ?? [:]
        for sectionDetail in details {
            
            if let value = sectionDetail.value as? [String: AnyObject] {
                var phones = [Contact]()
                for contacts in value {
                    let contact = Contact(contacts.key, phone: contacts.value)
                    phones.append(contact)
                }
                contactsSectionDetails[sectionDetail.key] = phones
            }
        }
        
        refreshUI()
    }
    
    func fetchContactsFromPLIST() {
        if
            let path = Bundle.main.path(forResource: APIConstants.PLIST_KEYS.NAME, ofType: "plist"),
            let myDict = NSDictionary(contentsOfFile: path),
            let json = myDict["contacts"] as? String
        {
            let data = json.data(using: .utf8)
            do {
                if let contents = try JSONSerialization.jsonObject(with: data!, options: []) as? [String: AnyObject] {
                    parseAndPopulateContacts(contents)
                }
            } catch {
                print(error)
            }
        }
    }
    
    func refreshUI() {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
        }
    }
}

// MARK: ContactsViewController -> UITableViewDataSource

extension ContactsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contactKeys.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: C.tableCellId)
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: C.tableCellId)
        }
        let contact = contactsSections[contactKeys[indexPath.row]]
        cell?.textLabel?.text = contact
        cell?.selectionStyle = .none
        return cell!
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sectionDetail = contactsSectionDetails[contactKeys[indexPath.row]]
        let departmentName = contactsSections[contactKeys[indexPath.row]] ?? "--"
        performSegue(withIdentifier: C.segueToList,
                     sender: [C.SEGUE_PAYLOAD_KEY.CONTACTS: sectionDetail ?? [],
                              C.SEGUE_PAYLOAD_KEY.DEPARTMENT_NAME: departmentName])
    }
}
