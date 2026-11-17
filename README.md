# Vendor Onboarding (Salesforce demo app)

## Why this repo exists

This repo is **demo material for a Salesforce DevOps tool**. The tool isn't in this repo. The repo stands in for any public or customer-owned GitHub repository that someone might want to bring into a Salesforce org.

It is meant to be small but realistic, so it has the kinds of metadata a real customer repo would have:

- a custom object with fields, validation rules, list views, history tracking, a layout and a Lightning record page
- a multi-step business process (a picklist plus a Lightning Path)
- a screen flow that calls an invocable Apex action, plus the Apex test class
- a Lightning app, tab and list view button
- two permission sets: a least-privilege end-user set and an app-admin set

It's not a product and isn't maintained as one. Use it in sandboxes and scratch orgs.

## The pretend business story

**Before:** Procurement tracks new vendors in a shared `Vendor Tracker.xlsx`.

1. An employee emails procurement: "We'd like to start using Acme for X."
2. Procurement adds a row to the spreadsheet and emails the vendor for a W-9 and a certificate of insurance.
3. When the documents come back, procurement emails Finance for approval and updates the Status column by hand.
4. Requests get lost in inboxes, nobody knows where a request stands, duplicate requests for the same vendor are common, and there's no audit trail.

**After (this app):**

1. The employee opens the **Vendor Onboarding** app and clicks **New Vendor Request**. A guided screen flow collects the details and warns if there's already an open or approved request for that vendor.
2. The request is created in **Submitted** status. The employee can see their own requests and nobody else's.
3. Procurement moves the request along the **Path**: Submitted → Under Review → Documents Requested → Finance Approval → Approved (or Rejected at any point).
4. Validation rules enforce the process. Requests can't skip stages, Finance can't see a request without a W-9, approval needs current insurance, rejections need a reason, and closed requests can't be reopened. Field history tracking records who changed what.

## What's in the box

| Path | What it is |
|---|---|
| `objects/Vendor_Onboarding__c/` | Custom object (`VO-0001` auto-number, Private sharing), 11 fields, 5 validation rules, 5 list views, a list view button |
| `pathAssistants/Vendor_Onboarding_Path` | Path on `Status__c` with per-stage guidance and key fields |
| `flows/New_Vendor_Request` | Screen flow: intake form → duplicate check → create record → confirmation |
| `classes/VendorDuplicateChecker` | `@InvocableMethod` used by the flow (with `VendorDuplicateCheckerTest`) |
| `layouts/`, `flexipages/` | Page layout and Lightning record page (highlights, Path, details, activity, related lists) |
| `tabs/`, `applications/Vendor_Onboarding` | Custom tab and Lightning app |
| `permissionsets/` | `Vendor_Onboarding_User` and `Vendor_Onboarding_Admin` (see below) |
| `data/sample-vendors.json` | Six sample requests, one in each stage |

### Fields on `Vendor_Onboarding__c`

| Field | Type | Notes |
|---|---|---|
| `Name` | Auto Number | `VO-{0000}` |
| `Vendor_Name__c` | Text(255) | Required |
| `Vendor_Contact_Email__c` | Email | |
| `Category__c` | Picklist | Software, Hardware, Professional Services, Facilities, Marketing, Other |
| `Estimated_Annual_Spend__c` | Currency | |
| `Business_Justification__c` | Long Text | |
| `Status__c` | Picklist | Submitted (default), Under Review, Documents Requested, Finance Approval, Approved, Rejected |
| `W9_Received__c` | Checkbox | |
| `Insurance_Expiry_Date__c` | Date | |
| `Requester__c` | Lookup(User) | Set by the flow |
| `Approver__c` | Lookup(User) | |
| `Rejection_Reason__c` | Text Area | |

## Permission sets

Each permission set is complete on its own. It works for a user on the **Minimum Access - Salesforce** profile, so neither one relies on extra permissions from a profile. Both assume a **Salesforce** user license.

### `Vendor_Onboarding_User`: requesters (least privilege)

| Area | Access |
|---|---|
| Object | Create, Read, Edit. No Delete, View All or Modify All. With the Private sharing model, users see only the requests they own. |
| Editable fields | Vendor Contact Email, Category, Estimated Annual Spend, Business Justification (and Vendor Name, which is required and so always editable) |
| Read-only fields | Status, W-9 Received, Insurance Expiry Date, Requester, Approver, Rejection Reason |
| App / tab | Vendor Onboarding app and tab |
| Flow | `New_Vendor_Request`. The flow is set to *restrict access to enabled profiles or permission sets* (`isAdditionalPermissionRequiredToRun`), so this grant is what lets users run it. The org-wide "Run Flows" permission isn't needed and doesn't grant access. |
| Apex | `VendorDuplicateChecker` (needed by the flow) |
| System permissions | Lightning Experience User only |

The flow runs in *system mode with sharing*. That lets it set Requester and Status, which requesters can't edit themselves, while still respecting record visibility. `VendorDuplicateChecker` runs `without sharing` so it can find duplicates raised by other people. It only returns request numbers and statuses, never the other records' contents.

### `Vendor_Onboarding_Admin`: app administrators

Everything in the User set, plus:

| Area | Access |
|---|---|
| Object | Full CRUD, View All, Modify All |
| Fields | Read and Edit on all fields |
| Apex | Both classes |
| System permissions | View Setup and Configuration, Customize Application, Manage Flow, Author Apex, Modify Metadata Through Metadata API Functions, API Enabled, Lightning Experience User, View Roles and Role Hierarchy, Manage Custom Permissions, Manage Translation (the last three are Salesforce-enforced dependencies of Author Apex and Customize Application) |

> **Note on least privilege:** Salesforce can't limit Setup permissions to one app. Customize Application, Manage Flow and Author Apex apply to the **whole org**. This set is meant for sandboxes and demos. In production, a customer would decide how far to trust human admins. Many give these permissions only to a CI/DevOps integration user.

## Deploying

Prerequisites: the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) and an org you're authorized to (sandbox, scratch org or Developer Edition).

```bash
# Authorize an org (or create a scratch org from config/project-scratch-def.json)
sf org login web --alias vendor-demo
# sf org create scratch --definition-file config/project-scratch-def.json --alias vendor-demo --set-default

# Deploy and run this repo's tests
sf project deploy start --source-dir force-app --target-org vendor-demo --test-level RunSpecifiedTests --tests VendorDuplicateCheckerTest

# Give yourself access
sf org assign permset --name Vendor_Onboarding_Admin --target-org vendor-demo

# Optional: sample data
sf data import tree --files data/sample-vendors.json --target-org vendor-demo

# Open the app
sf org open --target-org vendor-demo --path lightning/o/Vendor_Onboarding__c/list
```

### Manifest (package.xml)

`manifest/package.xml` lists every component in `force-app`, for DevOps tools and change-set style deployments that expect a manifest:

```bash
sf project deploy start --manifest manifest/package.xml --target-org vendor-demo --test-level RunSpecifiedTests --tests VendorDuplicateCheckerTest

# Regenerate after adding or removing metadata
sf project generate manifest --source-dir force-app --output-dir manifest --name package.xml
```

To try the requester experience, create a user on the **Minimum Access - Salesforce** profile and assign `Vendor_Onboarding_User`. Requesters don't get API access, so to open the org as that user with `sf org open`, also give them a separate test-only permission set with API Enabled. Don't add it to `Vendor_Onboarding_User`.
