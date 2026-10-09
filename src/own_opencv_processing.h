#ifndef OPENCVPROCESSING_H
#define OPENCVPROCESSING_H

#include <opencv2/imgproc.hpp>
#include <opencv2/aruco.hpp>
#include <vector>

// Class untuk pemrosesan ArUco Marker menggunakan OpenCV
class OpenCVProcessing
{
    private:
        cv::Ptr<cv::aruco::Dictionary> dictionary;
        cv::Ptr<cv::aruco::DetectorParameters> detector_params;

        cv::Mat camera_matrix;
        cv::Mat dist_coeffs;
        float marker_length_m = 0.05f; // sisi marker fisik (meter), default 5 cm
        int calib_width = 0;
        int calib_height = 0;

        void ensure_camera_matrix(int width, int height);

    public:
        // Hasil pose frame terakhir (diisi tiap process_image, dikosongkan saat hilang)
        std::vector<int> last_ids;
        std::vector<cv::Vec3d> last_rvecs;
        std::vector<cv::Vec3d> last_tvecs;

        OpenCVProcessing();
        ~OpenCVProcessing();

        void set_marker_length(float meters);

        cv::Mat process_image(cv::Mat input, bool do_process);
};

#endif