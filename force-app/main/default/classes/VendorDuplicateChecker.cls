/**
 * Invocable action used by the New Vendor Request screen flow to warn the
 * requester when an open or approved request already exists for the same
 * vendor name or contact email.
 *
 * Queries in SYSTEM MODE on purpose: Vendor_Onboarding__c is Private, so a
 * requester can only see their own records and would miss duplicates raised
 * by colleagues. (The class is also declared without sharing, but the query
 * says WITH SYSTEM_MODE explicitly so the behavior doesn't depend on the API
 * version's default access mode.) To avoid leaking other people's requests, the action only
 * returns request numbers and statuses, never the full records.
 */
public without sharing class VendorDuplicateChecker {
    public class Request {
        @InvocableVariable(label='Vendor Name' required=true)
        public String vendorName;

        @InvocableVariable(label='Vendor Contact Email')
        public String contactEmail;
    }

    public class Result {
        @InvocableVariable(label='Has Duplicates')
        public Boolean hasDuplicates = false;

        @InvocableVariable(label='Duplicate Count')
        public Integer duplicateCount = 0;

        @InvocableVariable(label='Duplicate Summary' description='e.g. "VO-0003 (Under Review), VO-0007 (Approved)"')
        public String summary = '';
    }

    @InvocableMethod(
        label='Find Duplicate Vendor Requests'
        description='Finds non-rejected Vendor Onboarding requests with the same vendor name or contact email.'
        category='Vendor Onboarding'
    )
    public static List<Result> findDuplicates(List<Request> requests) {
        Set<String> names = new Set<String>();
        Set<String> emails = new Set<String>();
        for (Request req : requests) {
            if (String.isNotBlank(req.vendorName)) {
                names.add(req.vendorName.trim().toLowerCase());
            }
            if (String.isNotBlank(req.contactEmail)) {
                emails.add(req.contactEmail.trim().toLowerCase());
            }
        }

        List<Vendor_Onboarding__c> candidates = [
            SELECT Name, Vendor_Name__c, Vendor_Contact_Email__c, Status__c
            FROM Vendor_Onboarding__c
            WHERE Status__c != 'Rejected'
              AND (Vendor_Name__c IN :names OR Vendor_Contact_Email__c IN :emails)
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 2000
        ];

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            String name = req.vendorName == null ? '' : req.vendorName.trim().toLowerCase();
            String email = req.contactEmail == null ? '' : req.contactEmail.trim().toLowerCase();
            List<String> matches = new List<String>();
            for (Vendor_Onboarding__c c : candidates) {
                Boolean nameMatch = String.isNotBlank(name) && c.Vendor_Name__c != null
                    && c.Vendor_Name__c.trim().toLowerCase() == name;
                Boolean emailMatch = String.isNotBlank(email) && c.Vendor_Contact_Email__c != null
                    && c.Vendor_Contact_Email__c.toLowerCase() == email;
                if (nameMatch || emailMatch) {
                    matches.add(c.Name + ' (' + c.Status__c + ')');
                }
            }
            Result r = new Result();
            r.duplicateCount = matches.size();
            r.hasDuplicates = !matches.isEmpty();
            r.summary = String.join(matches, ', ');
            results.add(r);
        }
        return results;
    }
}
