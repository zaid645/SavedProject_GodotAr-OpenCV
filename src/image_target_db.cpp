#include "image_target_db.h"

#include <opencv2/calib3d.hpp>

ImageTargetDB::ImageTargetDB(int nfeatures) {
    orb = cv::ORB::create(nfeatures, 1.2f, 8);
}

ImageTargetDB::~ImageTargetDB() {}

cv::Mat ImageTargetDB::loadGray(const std::string &path) {
    cv::Mat img = cv::imread(path, cv::IMREAD_GRAYSCALE);
    return img;
}

cv::Mat ImageTargetDB::preprocess(const cv::Mat &gray) {
    cv::Mat small = gray;
    if (gray.cols > max_width) {
        double s = static_cast<double>(max_width) / gray.cols;
        cv::resize(gray, small,
            cv::Size(max_width, int(gray.rows * s)), 0, 0, cv::INTER_LINEAR);
    }
    cv::Mat eq;
    cv::equalizeHist(small, eq);
    cv::Mat out;
    cv::GaussianBlur(eq, out, cv::Size(3, 3), 0.5);
    return out;
}

int ImageTargetDB::addTarget(const std::string &png_path,
                             const std::string &name,
                             float width_m, std::string &err) {
    if (width_m <= 0.0f) { err = "width_m harus > 0"; return -1; }
    cv::Mat gray = loadGray(png_path);
    if (gray.empty()) { err = "gagal baca: " + png_path; return -1; }
    cv::Mat proc = preprocess(gray);
    std::vector<cv::KeyPoint> kps;
    cv::Mat desc;
    orb->detectAndCompute(proc, cv::noArray(), kps, desc);
    if ((int)kps.size() < 150) {
        err = "DITOLAK: terlalu polos";
        return (int)kps.size();
    }
    ImageTargetEntry e;
    e.name = name;
    e.image_path = png_path;
    e.width_m = width_m;
    e.height_m = width_m * ((double)proc.rows / (double)proc.cols);
    e.keypoints = kps;
    e.descriptors = desc;
    // ganti bila nama sama
    for (auto &t : targets) {
        if (t.name == name) { t = e; return (int)kps.size(); }
    }
    targets.push_back(e);
    return (int)kps.size();
}

void ImageTargetDB::clear() { targets.clear(); }

bool ImageTargetDB::saveYml(const std::string &path) {
    cv::FileStorage fs(path, cv::FileStorage::WRITE);
    if (!fs.isOpened()) return false;
    fs << "count" << (int)targets.size();
    for (size_t i = 0; i < targets.size(); ++i) {
        std::string n = "t" + std::to_string(i);
        fs << n << "{";
        fs << "name" << targets[i].name;
        fs << "image_path" << targets[i].image_path;
        fs << "width_m" << targets[i].width_m;
        fs << "height_m" << targets[i].height_m;
        fs << "keypoints" << targets[i].keypoints;
        fs << "descriptors" << targets[i].descriptors;
        fs << "}";
    }
    fs.release();
    return true;
}

bool ImageTargetDB::loadYml(const std::string &path) {
    cv::FileStorage fs(path, cv::FileStorage::READ);
    if (!fs.isOpened()) return false;
    int count = 0;
    fs["count"] >> count;
    targets.clear();
    for (int i = 0; i < count; ++i) {
        cv::FileNode n = fs["t" + std::to_string(i)];
        if (n.empty()) continue;
        ImageTargetEntry e;
        e.name = (std::string)n["name"];
        e.image_path = (std::string)n["image_path"];
        n["width_m"] >> e.width_m;
        n["height_m"] >> e.height_m;
        cv::read(n["keypoints"], e.keypoints);
        n["descriptors"] >> e.descriptors;
        targets.push_back(e);
    }
    fs.release();
    return true;
}
