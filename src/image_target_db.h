#ifndef IMAGE_TARGET_DB_H
#define IMAGE_TARGET_DB_H

#include <opencv2/features2d.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <string>
#include <vector>

// DB target gambar natural (ORB). File BARU Fase B1 — ArUco tak disentuh.
struct ImageTargetEntry {
    std::string name;
    std::string image_path;
    float width_m = 0.20f;
    float height_m = 0.20f;
    std::vector<cv::KeyPoint> keypoints;
    cv::Mat descriptors;
};

class ImageTargetDB {
private:
    cv::Ptr<cv::ORB> orb;
    std::vector<ImageTargetEntry> targets;
    int max_width = 480;

    cv::Mat preprocess(const cv::Mat &gray);

public:
    ImageTargetDB(int nfeatures = 750);
    ~ImageTargetDB();

    // return keypoint count, atau <0 + err bila gagal
    int addTarget(const std::string &png_path, const std::string &name,
                  float width_m, std::string &err);
    void clear();
    size_t size() const { return targets.size(); }
    const std::vector<ImageTargetEntry> &getTargets() const { return targets; }

    bool saveYml(const std::string &path);
    bool loadYml(const std::string &path);

    static cv::Mat loadGray(const std::string &path);
};

#endif
