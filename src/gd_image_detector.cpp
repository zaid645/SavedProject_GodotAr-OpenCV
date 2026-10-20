#include "gd_image_detector.h"

#include <Array.hpp>
#include <ProjectSettings.hpp>
#include <Vector3.hpp>

using namespace godot;

void GDImageDetector::_register_methods() {
    register_method("_process", &GDImageDetector::_process);
    register_method("load_target", &GDImageDetector::load_target);
    register_method("clear_db", &GDImageDetector::clear_db);
    register_method("target_count", &GDImageDetector::target_count);
    register_method("set_detect_every_n_frames", &GDImageDetector::set_detect_every_n_frames);
    register_method("set_min_inliers", &GDImageDetector::set_min_inliers);
    register_method("set_match_ratio", &GDImageDetector::set_match_ratio);
    register_property<GDImageDetector, int>("camera_id", &GDImageDetector::set_camera_id, &GDImageDetector::get_camera_id, 0);
    register_property<GDImageDetector, bool>("show_processed", &GDImageDetector::set_show_processed, &GDImageDetector::get_show_processed, false);
    register_property<GDImageDetector, int>("width", &GDImageDetector::width, 640);
    register_property<GDImageDetector, int>("height", &GDImageDetector::height, 480);
    register_signal<GDImageDetector>((char *)"frame_updated", "node", GODOT_VARIANT_TYPE_OBJECT, "image", GODOT_VARIANT_TYPE_OBJECT);
    register_signal<GDImageDetector>((char *)"image_detected",
        "node", GODOT_VARIANT_TYPE_OBJECT,
        "names", GODOT_VARIANT_TYPE_ARRAY,
        "translations", GODOT_VARIANT_TYPE_ARRAY,
        "rotations", GODOT_VARIANT_TYPE_ARRAY);
}

GDImageDetector::GDImageDetector() : matcher(cv::NORM_HAMMING) {}

GDImageDetector::~GDImageDetector() {
    if (cap != NULL) cap->release();
    if (!frame.empty()) frame.release();
    if (!output.empty()) output.release();
}

void GDImageDetector::_init() {
    camera_id = 0;
    show_processed = false;
    width = 640;
    height = 480;
    detect_every_n_frames = 2;
    min_inliers = 20;
    match_ratio = 0.75f;
    downscale_width = 480;
    cap = NULL;
    calib_w = 0;
    calib_h = 0;
    frame_counter = 0;
}


void GDImageDetector::_process(float delta) {
    (void)delta;
    if (cap == NULL) init_camera();
    if (cap->isOpened()) {
        if (cap->read(frame)) {
            output = frame.clone();
            frame_counter++;
            bool do_match = (frame_counter % detect_every_n_frames == 0);
            last_names.clear();
            last_rvecs.clear();
            last_tvecs.clear();
            if (do_match && db.size() > 0) {
                int64 t0 = cv::getTickCount();
                ensure_camera_matrix(frame.cols, frame.rows);
                cv::Mat gray;
                cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
                double sx0 = 1.0, sy0 = 1.0;
                if (gray.cols > downscale_width) {
                    sx0 = (double)gray.cols / downscale_width;
                    double s = (double)downscale_width / gray.cols;
                    cv::resize(gray, gray, cv::Size(downscale_width, int(gray.rows * s)));
                    sy0 = sx0;
                }
                std::vector<cv::KeyPoint> kps;
                cv::Mat desc;
                orb->detectAndCompute(gray, cv::noArray(), kps, desc);
                if (!desc.empty()) {
                    for (const auto &t : db.getTargets()) {
                        if (t.descriptors.empty()) continue;
                        std::vector<std::vector<cv::DMatch>> knn;
                        matcher.knnMatch(desc, t.descriptors, knn, 2);
                        std::vector<cv::Point2f> ps, qs;
                        for (auto &m : knn) {
                            if (m.size() < 2) continue;
                            if (m[0].distance < match_ratio * m[1].distance) {
                                ps.push_back(kps[m[0].queryIdx].pt);
                                qs.push_back(t.keypoints[m[0].trainIdx].pt);
                            }
                        }
                        if (ps.size() < 8) continue;
                        cv::Mat mask;
                        cv::Mat H = cv::findHomography(qs, ps, cv::RANSAC, 3.0, mask);
                        if (H.empty()) continue;
                        int inliers = 0;
                        for (int r = 0; r < mask.rows; ++r)
                            if (mask.at<uchar>(r)) inliers++;
                        if (inliers < min_inliers) continue;
                        float hw = t.width_m * 0.5f;
                        float hh = t.height_m * 0.5f;
                        std::vector<cv::Point3f> o3 = {
                            {-hw, -hh, 0}, {hw, -hh, 0}, {hw, hh, 0}, {-hw, hh, 0}};
                        std::vector<cv::Point2f> tc = {
                            {0.f, 0.f}, {320.f, 0.f}, {320.f, 240.f}, {0.f, 240.f}};
                        std::vector<cv::Point2f> fc;
                        cv::perspectiveTransform(tc, fc, H);
                        cv::Vec3d rvec, tvec;
                        if (!cv::solvePnP(o3, fc, camera_matrix, dist_coeffs, rvec, tvec))
                            continue;
                        last_names.push_back(t.name);
                        last_rvecs.push_back(rvec);
                        last_tvecs.push_back(tvec);
                        if (show_processed && !output.empty()) {
                            std::vector<std::vector<cv::Point>> poly(1);
                            for (auto &p : fc)
                                poly[0].push_back(cv::Point(int(p.x * sx0), int(p.y * sy0)));
                            cv::polylines(output, poly, true, cv::Scalar(0, 255, 0), 2);
                        }
                    }
                }
                double ms = (cv::getTickCount() - t0) * 1000.0 / cv::getTickFrequency();
                static int log_every = 0;
                if (++log_every % 60 == 0)
                    Godot::print(String("[IMG] match {0} target: {1} ms").format(Array::make((int)db.size(), ms)));
            }
            gd_frame = cvMat_to_Image();
            emit_signal("frame_updated", this, gd_frame);
            emit_image_signal();
        }
    }
}

void GDImageDetector::ensure_camera_matrix(int w, int h) {
    if (w <= 0 || h <= 0) return;
    if (w == calib_w && h == calib_h && !camera_matrix.empty()) return;
    double fx = 0.9 * (double)w;
    camera_matrix = (cv::Mat_<double>(3, 3) << fx, 0, w * 0.5, 0, fx, h * 0.5, 0, 0, 1);
    calib_w = w;
    calib_h = h;
}

void GDImageDetector::init_camera() {
    cap = new cv::VideoCapture(camera_id);
    if (cap->isOpened()) {
        cap->set(cv::CAP_PROP_FRAME_WIDTH, width);
        cap->set(cv::CAP_PROP_FRAME_HEIGHT, height);
    }
}

void GDImageDetector::set_camera_id(int c) { camera_id = c; }
int GDImageDetector::get_camera_id() { return camera_id; }
void GDImageDetector::set_show_processed(bool v) { show_processed = v; }
bool GDImageDetector::get_show_processed() { return show_processed; }
void GDImageDetector::set_detect_every_n_frames(int n) { if (n > 0) detect_every_n_frames = n; }
int GDImageDetector::get_detect_every_n_frames() { return detect_every_n_frames; }
void GDImageDetector::set_min_inliers(int n) { if (n > 0) min_inliers = n; }
int GDImageDetector::get_min_inliers() { return min_inliers; }
void GDImageDetector::set_match_ratio(float r) { if (r > 0 && r < 1) match_ratio = r; }
float GDImageDetector::get_match_ratio() { return match_ratio; }

bool GDImageDetector::load_target(String path, String name, float width_m) {
    std::string err;
    String abs = ProjectSettings::get_singleton()->globalize_path(path);
    int kp = db.addTarget(std::string(abs.utf8().get_data()), std::string(name.utf8().get_data()), width_m, err);
    if (kp < 0) {
        Godot::print(String("[IMG] load_target gagal: ") + String(err.c_str()));
        return false;
    }
    Godot::print(String("[IMG] target '{0}' dimuat ({1} kp)").format(Array::make(name, kp)));
    return true;
}

void GDImageDetector::clear_db() { db.clear(); }
int GDImageDetector::target_count() { return (int)db.size(); }

Ref<Image> GDImageDetector::cvMat_to_Image() {
    cv::Mat cv_rgb;
    cv::cvtColor(output, cv_rgb, cv::COLOR_BGR2RGB);
    int numel = cv_rgb.rows * cv_rgb.cols * cv_rgb.channels();
    PoolByteArray bytes;
    bytes.resize(numel);
    if (cv_rgb.isContinuous()) {
        std::memcpy(bytes.write().ptr(), cv_rgb.ptr(), numel);
    } else {
        const int row_bytes = cv_rgb.cols * cv_rgb.channels();
        uint8_t *dst = bytes.write().ptr();
        for (int r = 0; r < cv_rgb.rows; ++r)
            std::memcpy(dst + r * row_bytes, cv_rgb.ptr(r), row_bytes);
    }
    Ref<Image> img;
    img.instance();
    img->create_from_data(cv_rgb.cols, cv_rgb.rows, false, img->FORMAT_RGB8, bytes);
    return img;
}
