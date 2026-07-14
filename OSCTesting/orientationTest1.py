from ahrs.filters import Madgwick
import numpy as np
from ahrs.common.orientation import q2euler
from ahrs.common.quaternion import Quaternion

madgwick = Madgwick(frequency=25.0)

prev_q = np.array([1.0, 0.0, 0.0, 0.0])
curr_q = np.array([1.0, 0.0, 0.0, 0.0])

gyro_data = np.array([1, -2, 1.03])  #RADIANS
acc_data = np.array([0.5, 0.4, 9.81])   
mag_data = np.array([19.2, 3.4, -45.1])   

prev_q = curr_q.copy()
curr_q = madgwick.updateMARG(
    prev_q,
    gyr=gyro_data,
    acc=acc_data,
    mag=mag_data
)

delta_q = curr_q * np.linalg.inv(prev_q)


# print("Current Orientation Quaternion (w, x, y, z):")
# print(q)

euler = q2euler(delta_q) # IN RADIANS
print(np.degrees(euler))

