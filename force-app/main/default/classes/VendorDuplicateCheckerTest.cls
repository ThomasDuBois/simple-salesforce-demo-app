@IsTest
private class VendorDuplicateCheckerTest {
    private static final String ADMIN_ALIAS = 'vo_admin';
    private static final String REQUESTER_ALIAS = 'vo_req';

    @TestSetup
    static void setup() {
        User admin = newUser(ADMIN_ALIAS);
        User requester = newUser(REQUESTER_ALIAS);
        // Setup objects (users, permission set assignments) must be inserted
        // separately from regular records, hence runAs for the setup DML.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ admin, requester };
            insert new List<PermissionSetAssignment>{
                assign(admin, 'Vendor_Onboarding_Admin'),
                assign(requester, 'Vendor_Onboarding_User')
            };
        }
        // Existing requests are owned by the admin, so with Private sharing
        // the requester can't see them - the checker must still find them.
        System.runAs(admin) {
            insert new List<Vendor_Onboarding__c>{
                new Vendor_Onboarding__c(
                    Vendor_Name__c = 'Acme Supplies',
                    Vendor_Contact_Email__c = 'ap@acme.example.com',
                    Status__c = 'Under Review'
                ),
                new Vendor_Onboarding__c(
                    Vendor_Name__c = 'Globex Consulting',
                    Vendor_Contact_Email__c = 'billing@globex.example.com',
                    Status__c = 'Rejected',
                    Rejection_Reason__c = 'Not needed'
                )
            };
        }
    }

    private static User newUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = alias + '.' + Datetime.now().getTime() + '.' + Crypto.getRandomInteger();
        return new User(
            Alias = alias,
            Email = alias + '@example.com',
            Username = unique + '@vendor-onboarding.test',
            LastName = alias,
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static PermissionSetAssignment assign(User u, String permSetName) {
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = :permSetName LIMIT 1].Id;
        return new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
    }

    private static User requester() {
        return [SELECT Id FROM User WHERE Alias = :REQUESTER_ALIAS AND Username LIKE '%@vendor-onboarding.test' LIMIT 1];
    }

    private static VendorDuplicateChecker.Result check(String name, String email) {
        VendorDuplicateChecker.Request req = new VendorDuplicateChecker.Request();
        req.vendorName = name;
        req.contactEmail = email;
        VendorDuplicateChecker.Result result;
        System.runAs(requester()) {
            result = VendorDuplicateChecker.findDuplicates(new List<VendorDuplicateChecker.Request>{ req })[0];
        }
        return result;
    }

    @IsTest
    static void requesterCannotSeeOthersRequestsDirectly() {
        System.runAs(requester()) {
            Assert.areEqual(0, [SELECT COUNT() FROM Vendor_Onboarding__c], 'Private sharing should hide others\' requests');
        }
    }

    @IsTest
    static void matchesOnNameIgnoringCaseAndWhitespace() {
        VendorDuplicateChecker.Result r = check('  acme SUPPLIES ', null);
        Assert.isTrue(r.hasDuplicates);
        Assert.areEqual(1, r.duplicateCount);
        Assert.isTrue(r.summary.contains('(Under Review)'), r.summary);
    }

    @IsTest
    static void matchesOnEmail() {
        VendorDuplicateChecker.Result r = check('Acme Supplies Ltd', 'AP@acme.example.com');
        Assert.isTrue(r.hasDuplicates);
    }

    @IsTest
    static void ignoresRejectedRequests() {
        VendorDuplicateChecker.Result r = check('Globex Consulting', 'billing@globex.example.com');
        Assert.isFalse(r.hasDuplicates);
        Assert.areEqual(0, r.duplicateCount);
        Assert.areEqual('', r.summary);
    }

    @IsTest
    static void handlesBulkRequests() {
        List<VendorDuplicateChecker.Request> reqs = new List<VendorDuplicateChecker.Request>();
        for (Integer i = 0; i < 200; i++) {
            VendorDuplicateChecker.Request req = new VendorDuplicateChecker.Request();
            req.vendorName = Math.mod(i, 2) == 0 ? 'Acme Supplies' : 'Brand New Vendor ' + i;
            reqs.add(req);
        }
        List<VendorDuplicateChecker.Result> results;
        Test.startTest();
        System.runAs(requester()) {
            results = VendorDuplicateChecker.findDuplicates(reqs);
        }
        Test.stopTest();
        Assert.areEqual(200, results.size());
        Assert.isTrue(results[0].hasDuplicates);
        Assert.isFalse(results[1].hasDuplicates);
    }
}
