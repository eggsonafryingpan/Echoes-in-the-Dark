from ahrs.filters import Madgwick
import numpy as np

madgwick = Madgwick(frequency=25.0)

q = np.array([1.0, 0.0, 0.0, 0.0])

gyro_data = np.array([0.01, -0.02, 0.03]) 
acc_data = np.array([0.1, 0.2, 9.81])   
mag_data = np.array([19.2, 3.4, -45.1])   

q = madgwick.updateIMU(
    q,
    gyr=gyro_data,
    acc=acc_data
)

print("Current Orientation Quaternion (w, x, y, z):")
print(q)