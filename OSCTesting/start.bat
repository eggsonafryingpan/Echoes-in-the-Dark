start "testIMU" py -3.14 osctestEmotibitIMU.py
start "testElevation" py -3.14 osctestEmotibitElevation.py
start "OSCReciever" py -3.14 OSCReciever.py
start "IMUCalc" cmd /k py -3.14 IMUCalc_WORKING.py
start "elevationCalc" py -3.14 elevationCalc_WORKING.py