CREATE OR REPLACE PACKAGE BODY APPS.xxgpil_receipt_pkg
IS

   PROCEDURE create_receipt (p_receipt_id NUMBER)
   IS
      PRAGMA AUTONOMOUS_TRANSACTION;
      l_return_status       VARCHAR2 (10);
      l_msg_count           NUMBER;
      l_msg_data            VARCHAR2 (4000);
      l_cr_id               NUMBER;
      l_error_msg           VARCHAR2 (4000) := 'Error In CR Creation: ';
      l_cust_acct_id        NUMBER;
      l_location            VARCHAR2 (250);
      l_receipt_no          VARCHAR2 (50);
      l_business_line       VARCHAR2 (50);
      l_rct_cnt             NUMBER;
      l_doc_seq             VARCHAR2 (50);
      l_bank_acct_use_id    NUMBER;

      CURSOR cur_rct_dtl
      IS
         
         SELECT a.customer_id, a.receipt_id, a.gpil_book_bank,
                a.operating_unit, a.instrument_no, a.instrument_amt,
                a.transaction_date, a.instrument_date, a.credit_date,
                a.bank_name, a.payment_type, a.status, a.customer_name,
                a.remarks, b.receipt_site_id, b.customer_bill_site_id,
                b.amount, b.oracle_document_no, b.customer_bill_site_name
           FROM xxgpil_receipt_header a, xxgpil_receipt_lines b
          WHERE a.receipt_id = b.receipt_id
            AND a.status =  'Pending'
            AND a.receipt_id = p_receipt_id
            AND b.amount > 0;
            
   BEGIN
      BEGIN
         --fnd_global.apps_initialize (0, 50381, 222);
         fnd_global.apps_initialize (0, 50371, 222);
      END;
      

      FOR i IN cur_rct_dtl
      LOOP
         BEGIN
            mo_global.set_policy_context ('S', i.operating_unit);
         END;

         DBMS_OUTPUT.put_line ('Before Fetching BusinessLine'||l_error_msg);
         BEGIN
            SELECT attribute2
              INTO l_business_line
              FROM hz_cust_site_uses_all
             WHERE site_use_id = i.customer_bill_site_id;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               l_business_line := NULL;
               l_error_msg :=
                     l_error_msg
                  || 'Business Line Not Assigned for the Customer Site;';
               EXIT;
            WHEN OTHERS
            THEN
               l_business_line := NULL;
               l_error_msg :=
                     l_error_msg
                  || 'Error finding Business Line for the Customer Site;';
               EXIT;
         END;

         DBMS_OUTPUT.put_line ('Before fetching receipt lines'||l_error_msg);
         BEGIN
            SELECT   COUNT (*)
                INTO l_rct_cnt
                FROM xxgpil_receipt_lines b
               WHERE receipt_id = i.receipt_id AND amount = i.amount
            GROUP BY amount;
         EXCEPTION
            WHEN OTHERS
            THEN
               l_rct_cnt := 0;
               l_error_msg :=
                            l_error_msg || 'Error finding Duplicate records;';
         END;

         IF l_rct_cnt > 1
         THEN
            l_receipt_no := i.instrument_no || '-' || l_business_line;
         ELSIF l_rct_cnt = 1
         THEN
            l_receipt_no := i.instrument_no;
         END IF;

         DBMS_OUTPUT.put_line ('Before Fetching Cust Account Id'||l_error_msg);
         BEGIN
            SELECT cust_account_id
              INTO l_cust_acct_id
              FROM hz_cust_accounts
             WHERE cust_account_id = i.customer_id;
         EXCEPTION
            WHEN OTHERS
            THEN
               l_cust_acct_id := NULL;
               l_error_msg :=
                     l_error_msg
                  || 'Error finding Customer Account Id for the Customer;';
         END;

         DBMS_OUTPUT.put_line ('Before Fetching Location'||l_error_msg);
         BEGIN
            SELECT LOCATION
              INTO l_location
              FROM hz_cust_site_uses
             WHERE site_use_id = i.customer_bill_site_id;
         EXCEPTION
            WHEN OTHERS
            THEN
               l_cust_acct_id := NULL;
               l_error_msg :=
                    l_error_msg || 'Error finding Location for the Customer;';
         END;
         
         BEGIN
            SELECT BANK_ACCT_USE_ID
              INTO l_bank_acct_use_id
              FROM ce_bank_acct_uses_all
             WHERE bank_account_id = i.gpil_book_bank;
         EXCEPTION
             WHEN OTHERS
             THEN
                l_bank_acct_use_id := null;
               l_error_msg :=
                    l_error_msg || 'Error finding Remmitance Bank;';
         END;

         DBMS_OUTPUT.put_line ('Before Calling API'||l_error_msg);
         ar_receipt_api_pub.create_cash
            (p_api_version                     => 1.0,
             p_init_msg_list                   => fnd_api.g_true,
             p_validation_level                => fnd_api.g_valid_level_full,
             p_receipt_number                  => l_receipt_no,
                                  --i.instrument_no|| '-'|| i.receipt_site_id,
                                                    --CR.RECEIPT_NUMBER,
             --P_CUSTOMER_BANK_ACCOUNT_ID =>'1057',
             p_amount                          => i.amount,
             --CR.REC_AMOUNT,
             p_currency_code                   => 'INR',
             --CR.CURRENCY_CODE,
             p_commit                          => fnd_api.g_false,
             p_receipt_method_id               => 1000,
             --P_PAYMENT_TYPE_CODE,
             p_customer_id                     => l_cust_acct_id,
                                               --i.customer_id,
                                                    --P_CUSTOMER_ACC_ID,
             --P_CALLED_FROM                     => 'BR_FACTORED_WITH_RECOURSE',
             p_receipt_date                    => i.instrument_date,
             --CR.REC_DATE,
             p_maturity_date                   => i.credit_date,
                                                          --i.instrument_date,
             --CR.MATURITY_DATE,
             p_gl_date                         => i.transaction_date,
                                                         -- i.instrument_date,
             --P_ATTRIBUTE_REC                   => LT_ATTRIBUTE_REC,
             p_remittance_bank_account_id      => l_bank_acct_use_id,  --i.gpil_book_bank,
             --i.bank_name,
             p_cr_id                           => l_cr_id,
             p_org_id                          => i.operating_unit,
             -- ###### R12 CHANGE ########
             p_customer_site_use_id            => i.customer_bill_site_id,
             p_location                        => l_location,
             p_comments                        => i.remarks,
             x_return_status                   => l_return_status,
             x_msg_count                       => l_msg_count,
             x_msg_data                        => l_msg_data
            );

         IF l_return_status = 'S'
         THEN
            UPDATE xxgpil_receipt_header
               SET status = 'Confirmed'
             WHERE receipt_id = i.receipt_id;

            UPDATE xxgpil_receipt_lines
               SET oracle_document_no = (SELECT doc_sequence_value
                                           FROM ar_cash_receipts_all
                                          WHERE cash_receipt_id = l_cr_id
                                          -----------Added  to fix the wrong oracle documnet number by Sanjeev on 7-JUL-2020
                                            and customer_site_use_id= i.customer_bill_site_id
                                            and receipt_number=i.instrument_no
                                          )
             WHERE receipt_site_id = i.receipt_site_id
              and customer_bill_site_id=i.customer_bill_site_id;-----------Added  to fix the wrong oracle documnet number by Sanjeev on 7-JUL-2020
         ELSIF l_return_status <> 'S'
         THEN
            DBMS_OUTPUT.put_line (l_error_msg || l_msg_data);
            ROLLBACK;

            FOR em IN 1 .. l_msg_count
            LOOP
               l_error_msg := l_error_msg || l_msg_data;
            END LOOP;

            UPDATE xxgpil_receipt_lines
               SET oracle_document_no = l_error_msg
             WHERE receipt_site_id = i.receipt_site_id
             -----------Added  to fix the wrong error message by Sanjeev on 27-JUL-2021-----------
             and customer_bill_site_id=i.customer_bill_site_id
             and oracle_document_no is null;

            COMMIT;
            EXIT;
         END IF;

         COMMIT;
      END LOOP;

      --insert into xxgpil_receipt_header (receipt_id) values (p_receipt_id+12);
--      update xxgpil_receipt_lines
--      set oracle_document_no = p_receipt_id
--      where receipt_id = p_receipt_id;
      COMMIT;
   END create_receipt;

   PROCEDURE reverse_receipt (p_receipt_id NUMBER)
   AS
      l_return_status   VARCHAR2 (10);
      l_msg_count       NUMBER;
      l_msg_data        VARCHAR2 (4000);
      l_cr_id           NUMBER;
      l_error_msg       VARCHAR2 (4000) := 'Error In CR Reversal: ';

      CURSOR cur_rct_dtl
      IS
         SELECT a.customer_id, a.receipt_id, a.gpil_book_bank,
                a.operating_unit, a.instrument_no, a.instrument_amt,
                a.transaction_date, a.instrument_date, a.credit_date,
                a.bank_name, a.payment_type, a.status, a.customer_name,
                a.remarks, a.boun_rev_str reversal_remarks,
                b.receipt_site_id, b.customer_bill_site_id, b.amount,
                b.oracle_document_no, b.customer_bill_site_name
           FROM xxgpil_receipt_header a, xxgpil_receipt_lines b
          WHERE a.receipt_id = b.receipt_id
            AND a.status = 'Confirmed'
            AND a.receipt_id = p_receipt_id
            AND b.oracle_document_no IS NOT NULL
            AND b.amount > 0;
   BEGIN
      FOR j IN cur_rct_dtl
      LOOP
         BEGIN
            mo_global.set_policy_context ('S', j.operating_unit);
         END;

         SELECT cash_receipt_id
           INTO l_cr_id
           FROM ar_cash_receipts_all
          WHERE RECEIPT_NUMBER=j.instrument_no
            and PAY_FROM_CUSTOMER=j.customer_id
            and ORG_ID=j.operating_unit
            and doc_sequence_value =
                   NVL (SUBSTR (j.oracle_document_no,
                                1,
                                INSTR (j.oracle_document_no, ' ', 1, 1) - 1
                               ),
                        j.oracle_document_no
                       );

         ar_receipt_api_pub.REVERSE
                                (p_api_version                 => 1.0,
                                 p_cash_receipt_id             => l_cr_id,
                                                              --j.oracle_document_no,
                                                                                    --LN_CAH_ID,
                                 --  P_RECEIPT_NUMBER              => CR.RECEIPT_NUMBER,
                                 p_reversal_category_code      => 'REV',
                                 --P_REVERSAL_CATEGORY_CODE,
                                 p_reversal_reason_code        => 'PAYMENT REVERSAL',
                                 --P_REVERSAL_REASON_CODE,
                                 p_reversal_comments           => j.reversal_remarks,
                                                                                      --j.remarks,
                                 --P_ATTRIBUTE_REC               => LT_ATTRIBUTE_REC,
                                 x_return_status               => l_return_status,
                                 x_msg_count                   => l_msg_count,
                                 x_msg_data                    => l_msg_data
                                );

         IF l_return_status = 'S'
         THEN
            UPDATE xxgpil_receipt_header
               SET status = 'Reversed'
             WHERE receipt_id = j.receipt_id;

            UPDATE xxgpil_receipt_lines
               SET oracle_document_no =
                            j.oracle_document_no || ' / Successfully Reversed'
             WHERE receipt_site_id = j.receipt_site_id
                  and customer_bill_site_id=j.customer_bill_site_id;-----------Added  to fix the wrong error message by Sanjeev on 27-JUL-2021
         ELSIF l_return_status <> 'S'
         THEN
            ROLLBACK;

            FOR em IN 1 .. l_msg_count
            LOOP
               l_error_msg := l_error_msg || l_msg_data;
            END LOOP;

            UPDATE xxgpil_receipt_lines
               SET oracle_document_no =
                                  j.oracle_document_no || ' / ' || l_error_msg
             WHERE receipt_site_id = j.receipt_site_id
             and customer_bill_site_id=j.customer_bill_site_id;-----------Added  to fix the wrong error message by Sanjeev on 27-JUL-2021

            COMMIT;
            EXIT;
         END IF;

         COMMIT;
      END LOOP;
   END reverse_receipt;
END xxgpil_receipt_pkg;
/
