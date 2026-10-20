#ifndef GD_IMAGE_DETECTOR_H
#define GD_IMAGE_DETECTOR_H

#include <Godot.hpp>
#include <Sprite.hpp>
#include <Image.hpp>

#include <opencv2/opencv.hpp>

#include "image_target_db.h"

// Worker GDNative jalur IMAGE (TERPISAH dari GDOpenCVExample/ArUco).
// ORB detectAndCompute -> BFMatcher Hamming + Lowe -> findHomography RANSAC
// -> inliers >= min_inliers -> solvePnP 4 sudut -> sinyal image_detected.
namespace godot {

class GDImageDetector : public Sprite {
    GODOT_CLASS(GDImageDetector, Sprite)

private:
    int camera_id;
    int width;
    int height;
    bool show_processed;
    int detect_every_n_frames;
    int min_inliers;
    float match_ratio;
    int downscale_width;

    cv::VideoCapture *cap;
    cv::Mat frame;
    cv::Mat output;
    Ref<Image> gd_frame;
    ImageTargetDB db;
    cv::Ptr<cv::ORB> orb;
    cv::BFMatcher matcher;
    cv::Mat camera_matrix;
    cv::Mat dist_coeffs;
    int calib_w;
    int calib_h;
    int frame_counter;

    std::vector<std::string> last_names;
    std::vector<cv::Vec3d> last_rvecs;
    std::vector<cv::Vec3d> last_tvecs;

    void emit_image_signal();
    void ensure_camera_matrix(int w, int h);

public:
    static void _register_methods();

    GDImageDetector();
    ~GDImageDetector();

    void _init();
    void _process(float delta);

    void set_camera_id(int cam_id);
    int get_camera_id();
    void init_camera();

    Ref<Image> cvMat_to_Image();

    void set_show_processed(bool do_process);
    bool get_show_processed();

    void set_detect_every_n_frames(int n);
    int get_detect_every_n_frames();
    void set_min_inliers(int n);
    int get_min_inliers();
    void set_match_ratio(float r);
    float get_match_ratio();

    // DB API dipanggil ARImageSession (B3)
    bool load_target(String path, String name, float width_m);
    void clear_db();
    int target_count();
};

}

#endif
