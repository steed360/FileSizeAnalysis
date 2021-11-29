
/*

Objective: 

Create an analysis table to show the number of active customers and the churn/new customers  between periods. Each period is represented by a period start date. 
The way I have modelled this is that that all values (e.g. number of customers) represent the situation one minute before each reporting date, these 
figures are the state 'going into' each date.  It could be modified to have reporting dates be the last date of a period, which might be clearer.

Specifically a monthly snapshot (or annual snapshot) in which the three measures values are calculated:
- Number Active
- Number_New	(i.e: "Number In")
- Number_Lapsed (i.e. "Number Lapsed") 

The final table is aggregated over just each reporting date so individual customer details are just counted. 
The raw customer level table could be useful for more detailed analysis. 

Inputs:
dbo.Transactions
#DIM_MONTHS (created below)

If you modify DIM_MONTHS to only be first of each YEAR then the values for NUMBER_NEW and NUMBER_LAPSED should still calculate OK.

Outputs:
See last block of SQL below

Intermediate Steps:

#TRANSACTIONS_DERIVED_COLS						- Add date column: NEXT_TRANSACTION_DUE_BEFORE 
#INITIAL_TABLE									- For each Reporting Date, calculate for each customer flags: IS_ACTIVE, IS_LAPSED
#INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO			- ""                    "",calculate for each  customer flags: IS_NEW
#INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO_ADD_TRANS - For each customer, find all prevoius transactions up to reporting date and calculate 
                                                  Frequency, Recency, Value

*/

USE FileSize
GO


/*
Add the derived column NEXT_TRANSACTION_DUE_BEFORE
- This is in the absence of a reliable CANCELLATION date field.
*/

IF OBJECT_ID ('TRANSACTIONS_DERIVED_COLS', 'U') IS NOT NULL 
	DROP TABLE TRANSACTIONS_DERIVED_COLS

SELECT
Q_ADD_PREV_TRANS.*
,LAG (Q_ADD_PREV_TRANS.INCOME_DATE) OVER (PARTITION BY Q_ADD_PREV_TRANS.ID ORDER BY INCOME_DATE ASC) AS PREV_TRANSACTION_DATE
,DATEADD ( mm, MONTHS_TILL_NEXT_PAYMENT, Q_ADD_PREV_TRANS.INCOME_DATE) AS NEXT_TRANSACTION_DUE_BEFORE

INTO TRANSACTIONS_DERIVED_COLS

FROM (
	SELECT   t1.ID 
	        ,T1.TRANS_ID
            ,t1.Amount
            , t1.TransactionDate as ActualDate
            , CAST ( t1.TransactionDate AS DATE ) as INCOME_DATE
            ,12 AS MONTHS_TILL_NEXT_PAYMENT
			,'CASH' AS PRODUCT
			,T1.Is_First
            FROM dbo.Transactions t1
) Q_ADD_PREV_TRANS

/*
--------------------------------------------
Create  #DIM_MONTHS
- Just a cut down version for this demo.
--------------------------------------------
*/

IF OBJECT_ID ('TEMPDB..#DIM_MONTHS') IS NOT NULL 
	DROP TABLE #DIM_MONTHS

CREATE TABLE #DIM_MONTHS 
( DATE_ID DATE 
, CALENDAR_YEAR INTEGER
, MONTH_NO INTEGER
) 

DECLARE @YEAR INT =  2014;

WHILE @YEAR <= 2023

BEGIN
	DECLARE @MONTH INT =  1;
	WHILE @MONTH <= 12
	BEGIN
		IF @MONTH % 2 = 0 
 
			INSERT INTO #DIM_MONTHS 
			VALUES  ( DATEFROMPARTS ( @YEAR, @MONTH, 1)
					, @YEAR
					,@MONTH) 
		  SET @MONTH = @MONTH + 1;
	END
   SET @YEAR = @YEAR + 1;
END;

/*
--------------------------------------------
#INITIAL_TABLE

This is the main processing part. 
Cross Apply each Month to any transaction that appeared before the month date and then label any transactions that 
- a) Were active (they straddle the snapshot date)
- b) Had lapsed (they closed in the period before)
--------------------------------------------
*/

IF OBJECT_ID ('TEMPDB..#INITIAL_TABLE') IS NOT NULL 
	DROP TABLE #INITIAL_TABLE

SELECT 
Q_REPORTING_DATES.REPORTING_DATE
,PREV_REPORTING_DATE
,Q_REPORTING_DATES.CALENDAR_YEAR
,Q_REPORTING_DATES.MONTH_NO
,C_APPLY.*

INTO #INITIAL_TABLE
FROM
(
  SELECT DATE_ID AS REPORTING_DATE
,LAG ( DATE_ID ) OVER (ORDER BY DATE_ID) AS PREV_REPORTING_DATE

, CALENDAR_YEAR 
, MONTH_NO 
  FROM #DIM_MONTHS D1 
  WHERE D1.DATE_ID BETWEEN '2014-02-01' AND '2023-12-01'
) Q_REPORTING_DATES
 
CROSS  APPLY
(
		/*
		Calculate IS_LAPSED, IS_ACTIVE
		IS_NEW cannot be calculated directly.
		*/

			SELECT Q_TRANS_CLOSEST_TO_SNAPSHOT_END.*

			,CASE WHEN 
						Q_TRANS_CLOSEST_TO_SNAPSHOT_END.INCOME_DATE  < Q_REPORTING_DATES.REPORTING_DATE 
						AND Q_TRANS_CLOSEST_TO_SNAPSHOT_END.NEXT_TRANSACTION_DUE_BEFORE  >= Q_REPORTING_DATES.REPORTING_DATE 
			 THEN 1
			 ELSE 0 END AS IS_ACTIVE

		   ,CASE WHEN 
				Q_TRANS_CLOSEST_TO_SNAPSHOT_END.NEXT_TRANSACTION_DUE_BEFORE >= Q_REPORTING_DATES.PREV_REPORTING_DATE
				AND Q_TRANS_CLOSEST_TO_SNAPSHOT_END.NEXT_TRANSACTION_DUE_BEFORE < Q_REPORTING_DATES.REPORTING_DATE
			THEN 1 ELSE 0 END AS IS_LAPSED

			FROM 
			(	
				SELECT * 
				,ROW_NUMBER () OVER (PARTITION BY T1.ID ORDER BY INCOME_DATE DESC) AS TRANS_NUMBER_DESC
				FROM 
				TRANSACTIONS_DERIVED_COLS T1
 
				WHERE T1.INCOME_DATE  < Q_REPORTING_DATES.REPORTING_DATE
				AND   T1.INCOME_DATE  >= DATEADD ( YY, -2, Q_REPORTING_DATES.REPORTING_DATE)
			) Q_TRANS_CLOSEST_TO_SNAPSHOT_END
			WHERE Q_TRANS_CLOSEST_TO_SNAPSHOT_END.TRANS_NUMBER_DESC = 1 

) C_APPLY

ORDER BY id, income_date


/*
--------------------------------------------
#INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO

Take #INITIAL_TABLE and estimate whether a transaction was NEW from a reporting Month or Year.
If the reporting period is very wide, it is possible for a customer to be new and then lapsed in the same period.
The very simplest possibility is used here.
--------------------------------------------
*/


IF OBJECT_ID ('TEMPDB..#INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO') IS NOT NULL 
	DROP TABLE #INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO


SELECT 
Q.REPORTING_DATE
,Q.ID
,Q.IS_LAPSED
,Q.PREV_TRANSACTION_DATE
,Q.INCOME_DATE AS TRANSACTION_DATE


,CASE 

	  WHEN Q.IS_ACTIVE_PREVIOUS IS NULL					THEN 1 
	  WHEN Q.IS_ACTIVE_PREVIOUS =0 and q.IS_LAPSED_PREV = 0	AND Q.IS_ACTIVE  = 1   THEN 1 

      WHEN Q.IS_LAPSED_PREV   = 1 AND Q.IS_ACTIVE = 1 THEN 1 
	  --WHEN Q.IS_LAPSED_PREV   = 1 AND Q.IS_LAPSED = 1 THEN 1 
 ELSE 0 END AS IS_NEW

 ,Q.IS_ACTIVE

INTO #INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO

FROM (
	SELECT *
	, LAG ( T1.IS_ACTIVE ) OVER ( PARTITION BY ID, PRODUCT ORDER BY REPORTING_DATE ASC ) AS IS_ACTIVE_PREVIOUS
	, LAG ( T1.IS_LAPSED ) OVER ( PARTITION BY ID, PRODUCT ORDER BY REPORTING_DATE ASC)  AS IS_LAPSED_PREV
	FROM #INITIAL_TABLE T1
) Q
ORDER BY ID, REPORTING_DATE


/*
--------------------------------------------
#INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO_ADD_TRANS

Look at all of the transactions up to the transaction that is represented in each snapshot.  
This can be done quite simply with cross apply (again)
Now the count of transaction is frequency, the sum of all prevoius transactions is Lifetime Value (to this point)
and the latest transaction before the reporting month is recency.

--------------------------------------------
*/

IF OBJECT_ID ('TEMPDB..#INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO_ADD_TRANS') IS NOT NULL 
	DROP TABLE #INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO_ADD_TRANS


SELECT I.*
, CASE  WHEN  Q.LTV <= 200 THEN '£0-200' 
		WHEN  Q.LTV <= 400 THEN '£201-400' 
		WHEN  Q.LTV <= 600 THEN '£401-600' 
		ELSE 'Over 600'
 END AS LTV_BANDED



, CASE  WHEN  Q.NUM_TRANSCTIONS = 1 THEN 'One Trans' 
		WHEN  Q.NUM_TRANSCTIONS = 2  THEN 'Two Trans' 
		WHEN  Q.NUM_TRANSCTIONS <= 5  THEN '3-5 Trans' 
		WHEN  Q.NUM_TRANSCTIONS <= 10  THEN '6-10 Trans'
		WHEN  Q.NUM_TRANSCTIONS <= 20  THEN '11-20 Trans'
		ELSE 'Over 20'
 END AS FREQUENCY_BANDED

, Q.NUM_TRANSCTIONS


, CASE WHEN I.PREV_TRANSACTION_DATE IS NULL THEN 'New' 
       WHEN DATEDIFF (MM, I.PREV_TRANSACTION_DATE, I.TRANSACTION_DATE )  <= 12 THEN '0-12 Months' 
       WHEN DATEDIFF (MM, I.PREV_TRANSACTION_DATE, I.TRANSACTION_DATE ) <= 24  THEN '13-24 Months' 
       WHEN DATEDIFF (MM, I.PREV_TRANSACTION_DATE, I.TRANSACTION_DATE ) > 24   THEN 'Over 24 Months' 
	   else 'OTHER' 
	END AS RECENCY_BANDED

INTO #INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO_ADD_TRANS
FROM 
#INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO I
CROSS APPLY (
	SELECT 
	  SUM ( T1.Amount ) AS LTV
	, COUNT (AMOUNT) AS NUM_TRANSCTIONS
	FROM transactions T1
	WHERE T1.ID = I.ID 
	AND  T1.TransactionDate < I.REPORTING_DATE
) Q

ORDER BY  i.id,  I.REPORTING_DATE

/*
--------------------------------------------
Final Tables is Just an aggregation over banded recency, frequency and value where we count the number of customers at each reportig month.
--------------------------------------------
*/



SELECT REPORTING_DATE
,YEAR (REPORTING_DATE) AS CALENDAR_YEAR
,MONTH ( REPORTING_DATE) AS MONTH_NO 
, SUM ( IS_ACTIVE) AS CASH_IS_ACTIVE ,  SUM (IS_NEW) AS CASH_IS_NEW, SUM (IS_LAPSED) AS CASH_IS_LAPSED
,RECENCY_BANDED
,FREQUENCY_BANDED
,LTV_BANDED
FROM #INITIAL_TABLE_ADD_PREV_SNAPSHOT_INFO_ADD_TRANS t1
where t1.REPORTING_DATE >= '2015-01-01'
GROUP BY REPORTING_DATE
,RECENCY_BANDED
,FREQUENCY_BANDED
,LTV_BANDED
ORDER BY REPORTING_DATE

