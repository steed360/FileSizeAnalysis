# FileSizeAnalysis
Periodic Snapshots Showing Active File Size in a Direct Marketing Environment

The active file is a marketing term describing the number of customers who have transacted within a certain time frame.  
Active customers may have a high propensity to purchase again and because they are easily reachable (permissions) allowing 
the size of the file is relevant to future sales forecasting, historic marketing effectiveness and some other analytical tasks.

This repo is for simulating customer transactions and then using these to calculate the size of the active file over a range of 
reporting snapshot dates. 

This has been done in a Tableau Public worksheet : 
https://public.tableau.com/app/profile/john.steedman/viz/ActiveFileSizeWithSimulatedData/FilesSize_Monthly?publish=yes&fbclid=IwAR1oKLf40pWs1uLjJqn2GNOYZA2jUk9N8ENkBqNsLfn-uI_gsZ4PSZvFnA8

And described lugubriously in a YT video here:
https://www.youtube.com/watch?v=toieZmcz2ZQ

Contents:

GenerateFile.ipynb             - Create transactions.csv:  a simulated set of customers and their transactions
Calculate_File_Size_Trends.SQL - Create the table that is read into Tableau (*)

* In fact it was run twice: once for monthly snapshots and once for Quarterly snapshots - the tableau viz will show both using a toggle.

